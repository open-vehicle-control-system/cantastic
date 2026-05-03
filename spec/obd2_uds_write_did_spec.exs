defmodule Cantastic.OBD2.UdsWriteDidSpec do
  use ESpec
  alias Cantastic.OBD2.{Request, RequestSpecification, ParameterSpecification, Response}
  alias Cantastic.{SocketMessage, FakeSocket}
  alias Decimal, as: D

  @process_name :CantasticTestNetworkUdsWriteOBD2Request

  defp param(overrides) do
    base = %ParameterSpecification{
      name: "did_value",
      id: 0xF190,
      kind: "bytes",
      precision: 0,
      network_name: :test_network,
      request_name: "uds_write",
      value_length: 8,
      endianness: "big",
      unit: nil,
      scale: D.new(1),
      offset: D.new(0),
      sign: "unsigned"
    }

    Map.merge(base, Map.new(overrides))
  end

  defp request_spec(parameter, options) do
    %RequestSpecification{
      name: "uds_write",
      request_frame_id: 0x7E0,
      response_frame_id: 0x7E8,
      frequency: 100,
      mode: 0x2E,
      parameter_specifications: [parameter],
      can_interface: "vcan_test",
      options: options
    }
  end

  defp start(parameter, options) do
    {:ok, pid} =
      Request.start_link(%{
        process_name: @process_name,
        request_specification: request_spec(parameter, options)
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

  describe "writing a DID (Mode 0x2E)" do
    context "when the ECU acknowledges the write" do
      it "delivers a positive response with empty parameters" do
        pid = start(param(%{id: 0xF40D}), %{data: <<0x55>>})

        try do
          :ok = Request.subscribe(self(), :test_network, "uds_write")
          FakeSocket.push_recv(<<0x6E, 0xF4, 0x0D>>)
          :ok = Request.enable(:test_network, "uds_write")

          assert_receive {:handle_obd2_response, %Response{mode: 0x6E, parameters: parameters}}, 1_000
          expect(parameters) |> to(eq(%{}))
        after
          shutdown(pid)
        end
      end
    end

    context "the bytes sent on the bus" do
      it "encode SID, DID (16-bit big-endian), and the options.data payload" do
        pid = start(param(%{id: 0x1234}), %{data: <<0xAA, 0xBB, 0xCC>>})

        try do
          :ok = Request.subscribe(self(), :test_network, "uds_write")
          FakeSocket.push_recv(<<0x6E, 0x12, 0x34>>)
          :ok = Request.enable(:test_network, "uds_write")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x2E, 0x12, 0x34, 0xAA, 0xBB, 0xCC>>))
        after
          shutdown(pid)
        end
      end
    end

    context "when the ECU rejects the write with security access denied" do
      it "delivers a :handle_obd2_error and stays alive" do
        pid = start(param(%{id: 0xF40D}), %{data: <<0x55>>})

        try do
          :ok = Request.subscribe(self(), :test_network, "uds_write")
          FakeSocket.push_recv(<<0x7F, 0x2E, 0x33>>)
          :ok = Request.enable(:test_network, "uds_write")

          assert_receive {:handle_obd2_error, {:nrc, 0x2E, 0x33, :security_access_denied}}, 1_000
          expect(Process.alive?(pid)) |> to(be_true())
        after
          shutdown(pid)
        end
      end
    end
  end
end
