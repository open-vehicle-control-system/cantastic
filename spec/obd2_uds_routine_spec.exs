defmodule Cantastic.OBD2.UdsRoutineSpec do
  use ESpec
  alias Cantastic.OBD2.{Request, RequestSpecification, Response}
  alias Cantastic.{SocketMessage, FakeSocket}

  @process_name :CantasticTestNetworkUdsRoutineOBD2Request

  defp request_spec(options) do
    %RequestSpecification{
      name: "uds_routine",
      request_frame_id: 0x7E0,
      response_frame_id: 0x7E8,
      frequency: 100,
      mode: 0x31,
      parameter_specifications: [],
      can_interface: "vcan_test",
      options: options
    }
  end

  defp start(options) do
    {:ok, pid} =
      Request.start_link(%{
        process_name: @process_name,
        request_specification: request_spec(options)
      })

    pid
  end

  defp shutdown(pid) do
    if Process.alive?(pid) do
      Process.unlink(pid)
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        500 -> :ok
      end
    end
  end

  before do
    allow(Cantastic.Socket)
    |> to(
      accept(:bind_isotp, fn _iface, _req_id, _resp_id, _padding ->
        {:ok, :fake_isotp_socket}
      end)
    )

    allow(Cantastic.Socket)
    |> to(
      accept(:send, fn _socket, raw ->
        FakeSocket.record_send(raw)
        :ok
      end)
    )

    allow(Cantastic.Socket)
    |> to(
      accept(:receive_message, fn _socket ->
        raw = FakeSocket.pop_recv()
        {:ok, %SocketMessage{raw: raw, reception_timestamp: 0}}
      end)
    )

    :ok
  end

  describe "starting a routine (Mode 0x31, sub-function 0x01)" do
    context "with the default sub-function and a routine_id" do
      it "sends 0x31 0x01 followed by the 16-bit routine id" do
        pid = start(%{routine_id: 0x0203})

        try do
          :ok = Request.subscribe(self(), :test_network, "uds_routine")
          # Response: 0x71 0x01 0x02 0x03 (no status record)
          FakeSocket.push_recv(<<0x71, 0x01, 0x02, 0x03>>)
          :ok = Request.enable(:test_network, "uds_routine")

          assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x31, 0x01, 0x02, 0x03>>))
          expect(parameters["routine_status"].value) |> to(eq(<<>>))
        after
          shutdown(pid)
        end
      end
    end

    context "with input_data appended to the request" do
      it "sends the input_data verbatim after the routine id" do
        pid = start(%{routine_id: 0xFF00, input_data: <<0xAA, 0xBB>>})

        try do
          :ok = Request.subscribe(self(), :test_network, "uds_routine")
          FakeSocket.push_recv(<<0x71, 0x01, 0xFF, 0x00>>)
          :ok = Request.enable(:test_network, "uds_routine")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x31, 0x01, 0xFF, 0x00, 0xAA, 0xBB>>))
        after
          shutdown(pid)
        end
      end
    end
  end

  describe "querying routine results (Mode 0x31, sub-function 0x03)" do
    it "surfaces the status_record as raw bytes under routine_status" do
      pid = start(%{routine_id: 0x0203, sub_function: 0x03})

      try do
        :ok = Request.subscribe(self(), :test_network, "uds_routine")
        # 0x71 0x03 0x02 0x03 + 4-byte status_record
        FakeSocket.push_recv(<<0x71, 0x03, 0x02, 0x03, 0xDE, 0xAD, 0xBE, 0xEF>>)
        :ok = Request.enable(:test_network, "uds_routine")

        assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
        expect(parameters["routine_status"].value) |> to(eq(<<0xDE, 0xAD, 0xBE, 0xEF>>))
        expect(parameters["routine_status"].kind) |> to(eq("bytes"))
      after
        shutdown(pid)
      end
    end
  end

  describe "stopping a routine (Mode 0x31, sub-function 0x02)" do
    it "sends the stop sub-function with the routine id" do
      pid = start(%{routine_id: 0x0203, sub_function: 0x02})

      try do
        :ok = Request.subscribe(self(), :test_network, "uds_routine")
        FakeSocket.push_recv(<<0x71, 0x02, 0x02, 0x03>>)
        :ok = Request.enable(:test_network, "uds_routine")

        assert_receive {:handle_obd2_response, _}, 1_000
        [first | _] = FakeSocket.sent()
        expect(first) |> to(eq(<<0x31, 0x02, 0x02, 0x03>>))
      after
        shutdown(pid)
      end
    end
  end

  describe "when the ECU rejects the routine" do
    it "delivers a :handle_obd2_error and stays alive" do
      pid = start(%{routine_id: 0x0203})

      try do
        :ok = Request.subscribe(self(), :test_network, "uds_routine")
        FakeSocket.push_recv(<<0x7F, 0x31, 0x33>>)
        :ok = Request.enable(:test_network, "uds_routine")

        assert_receive {:handle_obd2_error, {:nrc, 0x31, 0x33, :security_access_denied}}, 1_000
        expect(Process.alive?(pid)) |> to(be_true())
      after
        shutdown(pid)
      end
    end
  end
end
