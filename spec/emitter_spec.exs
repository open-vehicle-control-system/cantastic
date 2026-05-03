defmodule Cantastic.EmitterSpec do
  use ESpec
  alias Cantastic.{Emitter, Frame, FrameSpecification, SignalSpecification, FakeSocket}
  alias Decimal, as: D

  @emitter_process_name :CantasticTestNetworkDriveRequestEmitter

  defp throttle_signal_spec do
    %SignalSpecification{
      name: "throttle",
      network_name: :test_network,
      frame_id: 0x200,
      frame_name: "drive_request",
      kind: "integer",
      precision: 0,
      sign: "unsigned",
      endianness: "little",
      value_start: 0,
      value_length: 8,
      scale: D.new(1),
      offset: D.new(0)
    }
  end

  defp brake_signal_spec do
    %SignalSpecification{
      name: "brake",
      network_name: :test_network,
      frame_id: 0x200,
      frame_name: "drive_request",
      kind: "integer",
      precision: 0,
      sign: "unsigned",
      endianness: "little",
      value_start: 8,
      value_length: 8,
      scale: D.new(1),
      offset: D.new(0)
    }
  end

  defp drive_request_frame_spec(frequency) do
    %FrameSpecification{
      id: 0x200,
      name: "drive_request",
      network_name: :test_network,
      frequency: frequency,
      signal_specifications: [throttle_signal_spec(), brake_signal_spec()],
      data_length: 16,
      byte_number: 2,
      checksum_required: false
    }
  end

  defp data_payload(raw_frame) do
    <<_id::32, _byte_number::8, _pad::24, payload::binary-size(8)>> = raw_frame
    payload
  end

  describe "configuring and emitting frames" do
    before do
      allow(Cantastic.Socket)
      |> to(
        accept(:send, fn _socket, raw ->
          FakeSocket.record_send(raw)
          :ok
        end)
      )

      {:ok, pid} =
        Emitter.start_link(%{
          process_name: @emitter_process_name,
          frame_specification: drive_request_frame_spec(50),
          socket: :fake_socket,
          network_name: :test_network
        })

      {:shared, emitter_pid: pid}
    end

    finally do
      pid = shared.emitter_pid
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

    context "when configured with default parameter builder and initial data, then enabled" do
      it "periodically sends a frame whose payload encodes the configured signal values" do
        :ok =
          Emitter.configure(:test_network, "drive_request", %{
            parameters_builder_function: :default,
            initial_data: %{"throttle" => 0x12, "brake" => 0x34},
            enable: true
          })

        Process.sleep(120)

        sent = FakeSocket.sent()
        expect(length(sent) >= 2) |> to(be_true())

        for raw <- sent do
          expect(data_payload(raw)) |> to(eq(<<0x12, 0x34, 0, 0, 0, 0, 0, 0>>))
        end
      end
    end

    context "when send_frame/2 is called explicitly" do
      it "emits exactly one frame on demand" do
        :ok =
          Emitter.configure(:test_network, "drive_request", %{
            parameters_builder_function: :default,
            initial_data: %{"throttle" => 0x01, "brake" => 0x02}
          })

        Emitter.send_frame(:test_network, "drive_request")
        Process.sleep(30)

        [raw] = FakeSocket.sent()
        expect(data_payload(raw)) |> to(eq(<<0x01, 0x02, 0, 0, 0, 0, 0, 0>>))
      end
    end

    context "when update/3 changes the emitter's data" do
      it "the next emitted frame reflects the updated values" do
        :ok =
          Emitter.configure(:test_network, "drive_request", %{
            parameters_builder_function: :default,
            initial_data: %{"throttle" => 0, "brake" => 0}
          })

        :ok =
          Emitter.update(:test_network, "drive_request", fn data ->
            %{data | "throttle" => 0xAA, "brake" => 0xBB}
          end)

        Emitter.send_frame(:test_network, "drive_request")
        Process.sleep(30)

        [raw] = FakeSocket.sent()
        expect(data_payload(raw)) |> to(eq(<<0xAA, 0xBB, 0, 0, 0, 0, 0, 0>>))
      end
    end

    context "when disabled after being enabled" do
      it "stops emitting periodic frames" do
        :ok =
          Emitter.configure(:test_network, "drive_request", %{
            parameters_builder_function: :default,
            initial_data: %{"throttle" => 0x55, "brake" => 0xAA},
            enable: true
          })

        Process.sleep(120)
        :ok = Emitter.disable(:test_network, "drive_request")
        # Wait a moment for any in-flight :send_frame to drain.
        Process.sleep(20)
        count_after_disable = length(FakeSocket.sent())
        Process.sleep(150)

        expect(length(FakeSocket.sent())) |> to(eq(count_after_disable))
      end
    end

    context "when forward/2 routes an existing frame's bytes" do
      let :forwarded_frame, do: %Frame{
        id: 0x200,
        name: "drive_request",
        network_name: :test_network,
        raw_data: <<0x77, 0x88>>,
        byte_number: 2
      }

      it "sends the frame's wire-format bytes verbatim" do
        :ok =
          Emitter.configure(:test_network, "drive_request", %{
            parameters_builder_function: :default,
            initial_data: %{"throttle" => 0, "brake" => 0}
          })

        :ok = Emitter.forward(:test_network, forwarded_frame())
        Process.sleep(30)

        [raw] = FakeSocket.sent()
        expect(data_payload(raw)) |> to(eq(<<0x77, 0x88, 0, 0, 0, 0, 0, 0>>))
      end
    end
  end
end
