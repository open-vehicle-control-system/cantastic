defmodule Cantastic.OBD2.FreezeFrameSpec do
  use ESpec
  alias Cantastic.OBD2.{Request, RequestSpecification, ParameterSpecification, Response}
  alias Cantastic.{SocketMessage, FakeSocket}
  alias Decimal, as: D

  @process_name :CantasticTestNetworkFreezeFrameOBD2Request

  defp speed_at_fault_parameter_spec do
    %ParameterSpecification{
      name: "speed_at_fault",
      id: 0x0D,
      kind: "integer",
      precision: 0,
      network_name: :test_network,
      request_name: "freeze_frame",
      value_length: 8,
      endianness: "big",
      unit: "km/h",
      scale: D.new(1),
      offset: D.new(0),
      sign: "unsigned"
    }
  end

  defp rpm_at_fault_parameter_spec do
    %ParameterSpecification{
      name: "rpm_at_fault",
      id: 0x0C,
      kind: "decimal",
      precision: 2,
      network_name: :test_network,
      request_name: "freeze_frame",
      value_length: 16,
      endianness: "big",
      unit: "rpm",
      scale: D.new("0.25"),
      offset: D.new(0),
      sign: "unsigned"
    }
  end

  defp request_spec(parameters) do
    %RequestSpecification{
      name: "freeze_frame",
      request_frame_id: 0x7DF,
      response_frame_id: 0x7E8,
      frequency: 50,
      mode: 0x02,
      parameter_specifications: parameters,
      can_interface: "vcan_test"
    }
  end

  defp start(parameters) do
    {:ok, pid} =
      Request.start_link(%{
        process_name: @process_name,
        request_specification: request_spec(parameters)
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

  describe "reading a freeze frame (Mode 0x02)" do
    context "when the ECU returns a single PID's value at the time of the fault" do
      it "delivers the decoded parameter value" do
        pid = start([speed_at_fault_parameter_spec()])

        try do
          :ok = Request.subscribe(self(), :test_network, "freeze_frame")
          # 0x42 SID, 0x0D PID, 0x00 frame_no, 0x32 = 50 km/h
          FakeSocket.push_recv(<<0x42, 0x0D, 0x00, 0x32>>)
          :ok = Request.enable(:test_network, "freeze_frame")

          assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
          expect(parameters["speed_at_fault"].value) |> to(eq(50))
          expect(parameters["speed_at_fault"].unit) |> to(eq("km/h"))
        after
          shutdown(pid)
        end
      end
    end

    context "when the ECU returns several PIDs from the same freeze frame" do
      it "decodes each one in the order requested" do
        pid = start([speed_at_fault_parameter_spec(), rpm_at_fault_parameter_spec()])

        try do
          :ok = Request.subscribe(self(), :test_network, "freeze_frame")
          # 0x42, 0x0D, 0x00, 0x32, 0x0C, 0x00, 0x09, 0xC4
          # speed = 50 km/h, rpm = 0x09C4 * 0.25 = 625.0
          FakeSocket.push_recv(<<0x42, 0x0D, 0x00, 0x32, 0x0C, 0x00, 0x09, 0xC4>>)
          :ok = Request.enable(:test_network, "freeze_frame")

          assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
          expect(parameters["speed_at_fault"].value) |> to(eq(50))
          expect(D.eq?(parameters["rpm_at_fault"].value, D.new("625.00"))) |> to(be_true())
        after
          shutdown(pid)
        end
      end
    end

    context "the bytes sent on the bus" do
      it "sandwich a frame_number byte (0) between each PID" do
        pid = start([speed_at_fault_parameter_spec(), rpm_at_fault_parameter_spec()])

        try do
          :ok = Request.subscribe(self(), :test_network, "freeze_frame")
          FakeSocket.push_recv(<<0x42, 0x0D, 0x00, 0x32, 0x0C, 0x00, 0x09, 0xC4>>)
          :ok = Request.enable(:test_network, "freeze_frame")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x02, 0x0D, 0x00, 0x0C, 0x00>>))
        after
          shutdown(pid)
        end
      end
    end

    context "when there is no freeze frame stored and the ECU rejects" do
      it "delivers a :handle_obd2_error and stays alive" do
        pid = start([speed_at_fault_parameter_spec()])

        try do
          :ok = Request.subscribe(self(), :test_network, "freeze_frame")
          FakeSocket.push_recv(<<0x7F, 0x02, 0x31>>)
          :ok = Request.enable(:test_network, "freeze_frame")

          assert_receive {:handle_obd2_error, {:nrc, 0x02, 0x31, :request_out_of_range}}, 1_000
          expect(Process.alive?(pid)) |> to(be_true())
        after
          shutdown(pid)
        end
      end
    end
  end
end
