defmodule Cantastic.OBD2.VehicleInfoSpec do
  use ESpec
  alias Cantastic.OBD2.{Request, RequestSpecification, ParameterSpecification, Response}
  alias Cantastic.{SocketMessage, FakeSocket}
  alias Decimal, as: D

  defp vin_parameter_spec do
    %ParameterSpecification{
      name: "vin",
      id: 0x02,
      kind: "ascii",
      precision: 0,
      network_name: :test_network,
      request_name: "vehicle_info",
      value_length: 17 * 8,
      endianness: "big",
      unit: nil,
      scale: D.new(1),
      offset: D.new(0),
      sign: "unsigned"
    }
  end

  defp calibration_id_parameter_spec do
    %ParameterSpecification{
      name: "calibration_ids",
      id: 0x04,
      kind: "ascii",
      precision: 0,
      network_name: :test_network,
      request_name: "vehicle_info",
      value_length: 16 * 8,
      endianness: "big",
      unit: nil,
      scale: D.new(1),
      offset: D.new(0),
      sign: "unsigned"
    }
  end

  defp request_spec(parameter_spec) do
    %RequestSpecification{
      name: "vehicle_info",
      request_frame_id: 0x7DF,
      response_frame_id: 0x7E8,
      frequency: 50,
      mode: 0x09,
      parameter_specifications: [parameter_spec],
      can_interface: "vcan_test"
    }
  end

  @process_name :CantasticTestNetworkVehicleInfoOBD2Request

  defp start(parameter_spec) do
    {:ok, pid} =
      Request.start_link(%{
        process_name: @process_name,
        request_specification: request_spec(parameter_spec)
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

  describe "reading the VIN (Mode 0x09 PID 0x02)" do
    context "when the ECU returns a single VIN" do
      it "delivers a response carrying the VIN as a single-element list" do
        pid = start(vin_parameter_spec())

        try do
          :ok = Request.subscribe(self(), :test_network, "vehicle_info")
          FakeSocket.push_recv(<<0x49, 0x02, 0x01, "1HGBH41JXMN109186"::binary>>)
          :ok = Request.enable(:test_network, "vehicle_info")

          assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
          expect(parameters["vin"].value) |> to(eq(["1HGBH41JXMN109186"]))
          expect(parameters["vin"].kind) |> to(eq("ascii"))
        after
          shutdown(pid)
        end
      end
    end

    context "the bytes sent on the bus" do
      it "encode just the SID and PID — no batched ids" do
        pid = start(vin_parameter_spec())

        try do
          :ok = Request.subscribe(self(), :test_network, "vehicle_info")
          FakeSocket.push_recv(<<0x49, 0x02, 0x01, "1HGBH41JXMN109186"::binary>>)
          :ok = Request.enable(:test_network, "vehicle_info")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x09, 0x02>>))
        after
          shutdown(pid)
        end
      end
    end
  end

  describe "reading calibration IDs (Mode 0x09 PID 0x04)" do
    context "when the ECU reports two calibration IDs in one response" do
      it "delivers them as a list of strings in order" do
        pid = start(calibration_id_parameter_spec())

        try do
          :ok = Request.subscribe(self(), :test_network, "vehicle_info")
          FakeSocket.push_recv(
            <<0x49, 0x04, 0x02, "ABCDEFGHIJKLMNOP"::binary, "QRSTUVWXYZ012345"::binary>>
          )
          :ok = Request.enable(:test_network, "vehicle_info")

          assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
          expect(parameters["calibration_ids"].value)
          |> to(eq(["ABCDEFGHIJKLMNOP", "QRSTUVWXYZ012345"]))
        after
          shutdown(pid)
        end
      end
    end
  end

  describe "when the ECU rejects the request" do
    it "delivers a :handle_obd2_error and stays alive" do
      pid = start(vin_parameter_spec())

      try do
        :ok = Request.subscribe(self(), :test_network, "vehicle_info")
        FakeSocket.push_recv(<<0x7F, 0x09, 0x12>>)
        :ok = Request.enable(:test_network, "vehicle_info")

        assert_receive {:handle_obd2_error, {:nrc, 0x09, 0x12, :sub_function_not_supported}}, 1_000
        expect(Process.alive?(pid)) |> to(be_true())
      after
        shutdown(pid)
      end
    end
  end
end
