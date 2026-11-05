defmodule Cantastic.ReceivedFrameWatcherSpec do
  use ESpec
  alias Cantastic.{Frame, FrameSpecification, ReceivedFrameWatcher}

  @network_name :watcher_test_network
  @frame_name "heartbeat"
  @frequency_ms 20
  @year_us 365 * 24 * 3600 * 1_000_000

  defp heartbeat_frame_spec do
    %FrameSpecification{
      id: 0x300,
      name: @frame_name,
      network_name: @network_name,
      frequency: @frequency_ms,
      frame_handlers: [],
      allowed_frequency_leeway: 10,
      allowed_missing_frames: 0,
      allowed_missing_frames_period: 1_000,
      required_on_time_frames: 3,
      signal_specifications: [],
      byte_number: 0
    }
  end

  defp send_heartbeats(watcher_pid, count, reception_timestamp_fun) do
    for frame_number <- 1..count do
      frame = %Frame{
        id: 0x300,
        name: @frame_name,
        network_name: @network_name,
        reception_timestamp: reception_timestamp_fun.(frame_number)
      }

      send(watcher_pid, {:handle_frame, frame})
      Process.sleep(@frequency_ms)
    end
  end

  before do
    {:ok, pid} =
      ReceivedFrameWatcher.start_link(%{
        process_name: :CantasticWatcherTestNetworkHeartbeatReceivedFrameWatcher,
        frame_specification: heartbeat_frame_spec(),
        network_name: @network_name
      })

    :ok = ReceivedFrameWatcher.subscribe(@network_name, @frame_name, self())
    :ok = ReceivedFrameWatcher.enable(@network_name, @frame_name)
    {:shared, watcher_pid: pid}
  end

  finally do
    pid = shared.watcher_pid
    Process.unlink(pid)
    Process.exit(pid, :kill)
  end

  context "when the wall clock steps while frames arrive on time" do
    it "keeps the frame alive" do
      base_us = System.os_time(:microsecond)

      send_heartbeats(shared.watcher_pid, 20, fn
        frame_number when frame_number <= 10 -> base_us + frame_number * @frequency_ms * 1_000
        frame_number -> base_us + @year_us + frame_number * @frequency_ms * 1_000
      end)

      expect(ReceivedFrameWatcher.is_alive?(@network_name, @frame_name)) |> to(eq({:ok, true}))
      refute_received {:handle_missing_frame, @network_name, @frame_name}
    end
  end

  context "when frames stop arriving" do
    it "reports the missing frame" do
      send_heartbeats(shared.watcher_pid, 10, fn _ -> 0 end)

      assert_receive {:handle_missing_frame, @network_name, @frame_name}, 500
      expect(ReceivedFrameWatcher.is_alive?(@network_name, @frame_name)) |> to(eq({:ok, false}))
    end
  end
end
