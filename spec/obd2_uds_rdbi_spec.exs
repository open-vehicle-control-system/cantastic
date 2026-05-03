defmodule Cantastic.OBD2.UdsRdbiSpec do
  use ESpec
  alias Cantastic.OBD2.{Request, RequestSpecification, ParameterSpecification, Response}
  alias Cantastic.{SocketMessage, FakeSocket}
  alias Decimal, as: D

  @process_name :CantasticTestNetworkUdsReadOBD2Request

  defp param_spec(overrides) do
    base = %ParameterSpecification{
      name: "did_value",
      id: 0xF190,
      kind: "integer",
      precision: 0,
      network_name: :test_network,
      request_name: "uds_read",
      value_length: 8,
      endianness: "big",
      unit: nil,
      scale: D.new(1),
      offset: D.new(0),
      sign: "unsigned"
    }

    Map.merge(base, Map.new(overrides))
  end

  defp request_spec(parameters) do
    %RequestSpecification{
      name: "uds_read",
      request_frame_id: 0x7E0,
      response_frame_id: 0x7E8,
      frequency: 50,
      mode: 0x22,
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

  describe "reading a single DID with an integer kind" do
    it "delivers the decoded value" do
      pid = start([param_spec(%{name: "battery_soc", id: 0xF40D, value_length: 8, unit: "%"})])

      try do
        :ok = Request.subscribe(self(), :test_network, "uds_read")
        # Response: SID 0x62, DID 0xF40D, value 75 (0x4B)
        FakeSocket.push_recv(<<0x62, 0xF4, 0x0D, 0x4B>>)
        :ok = Request.enable(:test_network, "uds_read")

        assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
        expect(parameters["battery_soc"].value) |> to(eq(75))
        expect(parameters["battery_soc"].unit) |> to(eq("%"))
      after
        shutdown(pid)
      end
    end
  end

  describe "reading a brand-specific DID with kind: bytes" do
    it "surfaces the raw payload so the caller can decode it themselves" do
      # Simulate a 4-cell voltages packed payload: 4 × 16-bit values
      pid = start([param_spec(%{name: "cell_voltages", id: 0x1234, kind: "bytes", value_length: 64})])

      try do
        :ok = Request.subscribe(self(), :test_network, "uds_read")
        FakeSocket.push_recv(<<0x62, 0x12, 0x34, 0x0F, 0xA0, 0x0F, 0xA1, 0x0F, 0xA2, 0x0F, 0xA3>>)
        :ok = Request.enable(:test_network, "uds_read")

        assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
        expect(parameters["cell_voltages"].value)
        |> to(eq(<<0x0F, 0xA0, 0x0F, 0xA1, 0x0F, 0xA2, 0x0F, 0xA3>>))
        expect(parameters["cell_voltages"].kind) |> to(eq("bytes"))
      after
        shutdown(pid)
      end
    end
  end

  describe "reading a DID with kind: ascii" do
    it "delivers the bytes as a string" do
      # DID 0xF190 is the standard UDS DID for VIN — 17 ASCII bytes.
      pid =
        start([
          param_spec(%{name: "vin", id: 0xF190, kind: "ascii", value_length: 17 * 8})
        ])

      try do
        :ok = Request.subscribe(self(), :test_network, "uds_read")
        FakeSocket.push_recv(<<0x62, 0xF1, 0x90, "1HGBH41JXMN109186"::binary>>)
        :ok = Request.enable(:test_network, "uds_read")

        assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
        expect(parameters["vin"].value) |> to(eq("1HGBH41JXMN109186"))
      after
        shutdown(pid)
      end
    end
  end

  describe "reading several DIDs in one request" do
    it "decodes each DID's value in the order requested" do
      pid =
        start([
          param_spec(%{name: "soc", id: 0xF40D, value_length: 8, unit: "%"}),
          param_spec(%{
            name: "rpm",
            id: 0xF40C,
            kind: "decimal",
            value_length: 16,
            scale: D.new("0.25")
          })
        ])

      try do
        :ok = Request.subscribe(self(), :test_network, "uds_read")
        # SID 0x62, DID 0xF40D, value 0x4B (75), DID 0xF40C, value 0x09C4 (625*4)
        FakeSocket.push_recv(<<0x62, 0xF4, 0x0D, 0x4B, 0xF4, 0x0C, 0x09, 0xC4>>)
        :ok = Request.enable(:test_network, "uds_read")

        assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
        expect(parameters["soc"].value) |> to(eq(75))
        expect(D.eq?(parameters["rpm"].value, D.new("625"))) |> to(be_true())
      after
        shutdown(pid)
      end
    end
  end

  describe "the bytes sent on the bus" do
    it "encode the SID followed by each DID as 16-bit big-endian" do
      pid =
        start([
          param_spec(%{name: "a", id: 0xF40D}),
          param_spec(%{name: "b", id: 0x1234})
        ])

      try do
        :ok = Request.subscribe(self(), :test_network, "uds_read")
        FakeSocket.push_recv(<<0x62, 0xF4, 0x0D, 0x00, 0x12, 0x34, 0x00>>)
        :ok = Request.enable(:test_network, "uds_read")

        assert_receive {:handle_obd2_response, _}, 1_000
        [first | _] = FakeSocket.sent()
        expect(first) |> to(eq(<<0x22, 0xF4, 0x0D, 0x12, 0x34>>))
      after
        shutdown(pid)
      end
    end
  end

  describe "when the ECU returns a UDS negative response" do
    it "delivers a :handle_obd2_error and stays alive" do
      pid = start([param_spec(%{name: "secured", id: 0xFD00})])

      try do
        :ok = Request.subscribe(self(), :test_network, "uds_read")
        # 0x7F SID 0x22 NRC 0x33 (security access denied)
        FakeSocket.push_recv(<<0x7F, 0x22, 0x33>>)
        :ok = Request.enable(:test_network, "uds_read")

        assert_receive {:handle_obd2_error, {:nrc, 0x22, 0x33, :security_access_denied}}, 1_000
        expect(Process.alive?(pid)) |> to(be_true())
      after
        shutdown(pid)
      end
    end
  end
end
