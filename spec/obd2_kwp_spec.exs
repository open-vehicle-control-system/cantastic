defmodule Cantastic.OBD2.KwpSpec do
  use ESpec
  alias Cantastic.OBD2.{Request, RequestSpecification, ParameterSpecification, Response}
  alias Cantastic.{SocketMessage, FakeSocket}
  alias Decimal, as: D

  defp param(overrides) do
    base = %ParameterSpecification{
      name: "value",
      id: 0x01,
      kind: "integer",
      precision: 0,
      network_name: :test_network,
      request_name: "kwp_request",
      value_length: 8,
      endianness: "big",
      unit: nil,
      scale: D.new(1),
      offset: D.new(0),
      sign: "unsigned"
    }

    Map.merge(base, Map.new(overrides))
  end

  defp request_spec(name, mode, parameters) do
    %RequestSpecification{
      name: name,
      request_frame_id: 0x7E0,
      response_frame_id: 0x7E8,
      frequency: 100,
      mode: mode,
      parameter_specifications: parameters,
      can_interface: "vcan_test",
      options: %{}
    }
  end

  defp start(name, mode, parameters) do
    process_name = String.to_atom("CantasticTestNetwork#{Macro.camelize(name)}OBD2Request")

    {:ok, pid} =
      Request.start_link(%{
        process_name: process_name,
        request_specification: request_spec(name, mode, parameters)
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

  describe "KWP2000 Mode 0x21 (ReadDataByLocalIdentifier)" do
    context "with a single local identifier" do
      it "delivers the decoded value" do
        pid = start("kwp_read_lid", 0x21, [param(%{name: "engine_load", id: 0x05, unit: "%"})])

        try do
          :ok = Request.subscribe(self(), :test_network, "kwp_read_lid")
          # 0x61 SID echo, 0x05 lid, 0x42 = 66
          FakeSocket.push_recv(<<0x61, 0x05, 0x42>>)
          :ok = Request.enable(:test_network, "kwp_read_lid")

          assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
          expect(parameters["engine_load"].value) |> to(eq(0x42))
        after
          shutdown(pid)
        end
      end
    end

    context "with multiple local identifiers in a single request" do
      it "decodes them positionally, like Mode 0x01" do
        pid =
          start("kwp_read_multi", 0x21, [
            param(%{name: "speed", id: 0x05, value_length: 8}),
            param(%{name: "rpm", id: 0x07, kind: "decimal", value_length: 16, scale: D.new("0.25")})
          ])

        try do
          :ok = Request.subscribe(self(), :test_network, "kwp_read_multi")
          FakeSocket.push_recv(<<0x61, 0x05, 0x32, 0x07, 0x09, 0xC4>>)
          :ok = Request.enable(:test_network, "kwp_read_multi")

          assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
          expect(parameters["speed"].value) |> to(eq(50))
          expect(D.eq?(parameters["rpm"].value, D.new("625"))) |> to(be_true())
        after
          shutdown(pid)
        end
      end
    end

    context "the bytes sent on the bus" do
      it "encode the SID followed by each local identifier" do
        pid =
          start("kwp_read_multi", 0x21, [
            param(%{name: "a", id: 0x01}),
            param(%{name: "b", id: 0x05})
          ])

        try do
          :ok = Request.subscribe(self(), :test_network, "kwp_read_multi")
          FakeSocket.push_recv(<<0x61, 0x01, 0x10, 0x05, 0x20>>)
          :ok = Request.enable(:test_network, "kwp_read_multi")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x21, 0x01, 0x05>>))
        after
          shutdown(pid)
        end
      end
    end
  end

  describe "KWP2000 Mode 0x1A (ReadECUIdentification)" do
    context "for the standard VIN identification option (0x90)" do
      it "delivers the ASCII payload" do
        pid =
          start("kwp_ecu_id", 0x1A, [
            param(%{name: "vin", id: 0x90, kind: "ascii", value_length: 17 * 8})
          ])

        try do
          :ok = Request.subscribe(self(), :test_network, "kwp_ecu_id")
          FakeSocket.push_recv(<<0x5A, 0x90, "1HGBH41JXMN109186"::binary>>)
          :ok = Request.enable(:test_network, "kwp_ecu_id")

          assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
          expect(parameters["vin"].value) |> to(eq("1HGBH41JXMN109186"))
          expect(parameters["vin"].kind) |> to(eq("ascii"))
        after
          shutdown(pid)
        end
      end
    end

    context "the bytes sent on the bus" do
      it "encode the SID followed by the identification option byte" do
        pid =
          start("kwp_ecu_id", 0x1A, [
            param(%{name: "ecu_id", id: 0x87, kind: "ascii", value_length: 16 * 8})
          ])

        try do
          :ok = Request.subscribe(self(), :test_network, "kwp_ecu_id")
          FakeSocket.push_recv(<<0x5A, 0x87, "ECU_ID_PADDED__\0"::binary>>)
          :ok = Request.enable(:test_network, "kwp_ecu_id")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x1A, 0x87>>))
        after
          shutdown(pid)
        end
      end
    end
  end
end
