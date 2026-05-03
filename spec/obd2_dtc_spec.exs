defmodule Cantastic.OBD2.DtcSpec do
  use ESpec
  alias Cantastic.OBD2.{Request, RequestSpecification, Response}
  alias Cantastic.{SocketMessage, FakeSocket}

  defp request_spec(name, mode) do
    %RequestSpecification{
      name: name,
      request_frame_id: 0x7DF,
      response_frame_id: 0x7E8,
      frequency: 50,
      mode: mode,
      parameter_specifications: [],
      can_interface: "vcan_test"
    }
  end

  defp start(name, mode) do
    process_name = String.to_atom("CantasticTestNetwork#{Macro.camelize(name)}OBD2Request")

    {:ok, pid} =
      Request.start_link(%{
        process_name: process_name,
        request_specification: request_spec(name, mode)
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

  describe "reading stored DTCs (Mode 0x03)" do
    context "when the ECU reports no DTCs" do
      it "delivers a response with an empty list" do
        pid = start("stored_dtcs", 0x03)

        try do
          :ok = Request.subscribe(self(), :test_network, "stored_dtcs")
          FakeSocket.push_recv(<<0x43, 0x00>>)
          :ok = Request.enable(:test_network, "stored_dtcs")

          assert_receive {:handle_obd2_response, %Response{parameters: %{"dtcs" => %{value: []}}}}, 1_000
        after
          shutdown(pid)
        end
      end
    end

    context "when the ECU reports a single DTC" do
      it "delivers a response with the decoded code" do
        pid = start("stored_dtcs", 0x03)

        try do
          :ok = Request.subscribe(self(), :test_network, "stored_dtcs")
          FakeSocket.push_recv(<<0x43, 0x01, 0x03, 0x01>>)
          :ok = Request.enable(:test_network, "stored_dtcs")

          assert_receive {:handle_obd2_response, %Response{parameters: %{"dtcs" => %{value: ["P0301"]}}}}, 1_000
        after
          shutdown(pid)
        end
      end
    end

    context "when the ECU reports multiple DTCs from different systems" do
      it "delivers them all in the order received" do
        pid = start("stored_dtcs", 0x03)

        try do
          :ok = Request.subscribe(self(), :test_network, "stored_dtcs")
          # P0301, C0042, U0100
          FakeSocket.push_recv(<<0x43, 0x03, 0x03, 0x01, 0x40, 0x42, 0xC1, 0x00>>)
          :ok = Request.enable(:test_network, "stored_dtcs")

          assert_receive {:handle_obd2_response, %Response{parameters: %{"dtcs" => %{value: codes}}}}, 1_000
          expect(codes) |> to(eq(["P0301", "C0042", "U0100"]))
        after
          shutdown(pid)
        end
      end
    end

    context "the bytes sent on the bus" do
      it "are exactly the SID with no parameters" do
        pid = start("stored_dtcs", 0x03)

        try do
          :ok = Request.subscribe(self(), :test_network, "stored_dtcs")
          FakeSocket.push_recv(<<0x43, 0x00>>)
          :ok = Request.enable(:test_network, "stored_dtcs")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x03>>))
        after
          shutdown(pid)
        end
      end
    end
  end

  describe "reading pending DTCs (Mode 0x07)" do
    it "decodes a response from SID 0x47 the same way" do
      pid = start("pending_dtcs", 0x07)

      try do
        :ok = Request.subscribe(self(), :test_network, "pending_dtcs")
        FakeSocket.push_recv(<<0x47, 0x01, 0x04, 0x20>>)
        :ok = Request.enable(:test_network, "pending_dtcs")

        assert_receive {:handle_obd2_response, %Response{parameters: %{"dtcs" => %{value: ["P0420"]}}}}, 1_000
      after
        shutdown(pid)
      end
    end
  end

  describe "reading permanent DTCs (Mode 0x0A)" do
    it "decodes a response from SID 0x4A the same way" do
      pid = start("permanent_dtcs", 0x0A)

      try do
        :ok = Request.subscribe(self(), :test_network, "permanent_dtcs")
        FakeSocket.push_recv(<<0x4A, 0x01, 0xC1, 0x00>>)
        :ok = Request.enable(:test_network, "permanent_dtcs")

        assert_receive {:handle_obd2_response, %Response{parameters: %{"dtcs" => %{value: ["U0100"]}}}}, 1_000
      after
        shutdown(pid)
      end
    end
  end

  describe "clearing DTCs (Mode 0x04)" do
    context "when the ECU acknowledges the clear" do
      it "delivers a positive response with empty parameters" do
        pid = start("clear_dtcs", 0x04)

        try do
          :ok = Request.subscribe(self(), :test_network, "clear_dtcs")
          FakeSocket.push_recv(<<0x44>>)
          :ok = Request.enable(:test_network, "clear_dtcs")

          assert_receive {:handle_obd2_response, %Response{mode: 0x44, parameters: parameters}}, 1_000
          expect(parameters) |> to(eq(%{}))
        after
          shutdown(pid)
        end
      end

      it "sends just the 0x04 SID with no parameters on the bus" do
        pid = start("clear_dtcs", 0x04)

        try do
          :ok = Request.subscribe(self(), :test_network, "clear_dtcs")
          FakeSocket.push_recv(<<0x44>>)
          :ok = Request.enable(:test_network, "clear_dtcs")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x04>>))
        after
          shutdown(pid)
        end
      end
    end

    context "when the ECU rejects the clear with security access denied" do
      it "delivers a :handle_obd2_error and stays alive" do
        pid = start("clear_dtcs", 0x04)

        try do
          :ok = Request.subscribe(self(), :test_network, "clear_dtcs")
          FakeSocket.push_recv(<<0x7F, 0x04, 0x33>>)
          :ok = Request.enable(:test_network, "clear_dtcs")

          assert_receive {:handle_obd2_error, {:nrc, 0x04, 0x33, :security_access_denied}}, 1_000
          expect(Process.alive?(pid)) |> to(be_true())
        after
          shutdown(pid)
        end
      end
    end
  end
end
