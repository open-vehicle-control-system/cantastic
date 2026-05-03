defmodule Cantastic.ReceiverSpec do
  use ESpec
  alias Cantastic.{Receiver, Frame, FrameSpecification, SignalSpecification, SocketMessage, FakeSocket}
  alias Decimal, as: D

  @receiver_process_name :CantasticTestNetworkReceiver

  defp socketcan_frame(id, data) do
    byte_number = byte_size(data)
    padding = 8 - byte_number

    <<
      id::little-integer-size(32),
      byte_number::little-integer-size(8),
      0::24,
      data::binary,
      0::padding * 8
    >>
  end

  defp voltage_signal_spec do
    %SignalSpecification{
      name: "voltage",
      network_name: :test_network,
      frame_id: 0x100,
      frame_name: "battery_status",
      kind: "integer",
      precision: 2,
      sign: "unsigned",
      endianness: "little",
      value_start: 0,
      value_length: 16,
      scale: D.new(1),
      offset: D.new(0)
    }
  end

  defp battery_status_frame_spec do
    %FrameSpecification{
      id: 0x100,
      name: "battery_status",
      network_name: :test_network,
      signal_specifications: [voltage_signal_spec()],
      frame_handlers: [],
      data_length: 16,
      byte_number: 2,
      checksum_required: false
    }
  end

  describe "subscribing to a frame" do
    before do
      allow(Cantastic.Socket)
      |> to(
        accept(:receive_message, fn _socket ->
          raw = FakeSocket.pop_recv()
          {:ok, %SocketMessage{raw: raw, reception_timestamp: 0}}
        end)
      )

      {:ok, pid} =
        Receiver.start_link(%{
          process_name: @receiver_process_name,
          frame_specifications: %{0x100 => battery_status_frame_spec()},
          socket: :fake_socket,
          network_name: :test_network
        })

      {:shared, receiver_pid: pid}
    end

    finally do
      pid = shared.receiver_pid
      if Process.alive?(pid) do
        Process.unlink(pid)
        ref = Process.monitor(pid)
        Process.exit(pid, :kill)
        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        after
          500 -> :ok
        end
      end
    end

    context "when a known frame arrives on the bus" do
      it "delivers a :handle_frame message with the decoded signal values" do
        :ok = Receiver.subscribe(self(), :test_network, "battery_status")
        FakeSocket.push_recv(socketcan_frame(0x100, <<0x32, 0x00>>))

        assert_receive {:handle_frame, %Frame{name: "battery_status", signals: signals}}, 1_000
        expect(signals["voltage"].value) |> to(eq(50))
      end
    end

    context "when a frame arrives whose id is not in the spec map" do
      it "does not deliver any message to the subscriber" do
        :ok = Receiver.subscribe(self(), :test_network, "battery_status")
        FakeSocket.push_recv(socketcan_frame(0x999, <<0x00, 0x00>>))

        refute_receive {:handle_frame, _}, 200
      end
    end

    context "when no subscriber is registered for the arriving frame" do
      it "decodes silently without sending any message" do
        FakeSocket.push_recv(socketcan_frame(0x100, <<0x32, 0x00>>))
        refute_receive {:handle_frame, _}, 200
      end
    end

    context "when several frames arrive in succession" do
      it "delivers a :handle_frame message for each of them in order" do
        :ok = Receiver.subscribe(self(), :test_network, "battery_status")
        FakeSocket.push_recv(socketcan_frame(0x100, <<0x0A, 0x00>>))
        FakeSocket.push_recv(socketcan_frame(0x100, <<0x14, 0x00>>))
        FakeSocket.push_recv(socketcan_frame(0x100, <<0x1E, 0x00>>))

        assert_receive {:handle_frame, %Frame{signals: %{"voltage" => %{value: 10}}}}, 1_000
        assert_receive {:handle_frame, %Frame{signals: %{"voltage" => %{value: 20}}}}, 1_000
        assert_receive {:handle_frame, %Frame{signals: %{"voltage" => %{value: 30}}}}, 1_000
      end
    end
  end
end
