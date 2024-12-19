defmodule Cantastic.ReceivedFrameWatcher do
  use GenServer
  alias Cantastic.{Frame, Interface}


  def start_link(%{process_name: process_name} = args) do
    GenServer.start_link(__MODULE__, args, name: process_name)
  end

  @impl true
  def init(%{process_name:  _, frame_specification: frame_specification, network_name: network_name}) do
    :ok = Cantastic.Receiver.subscribe(self(), network_name, [frame_specification.name])
    now = System.monotonic_time(:millisecond)
    {:ok,
      %{
        watching_timer: nil,
        network_name: network_name,
        frame_a_received_at: nil,
        frame_b_received_at: nil,
        last_received_frame: :b,
        frame_name: frame_specification.name,
        frame_handlers: frame_specification.frame_handlers,
        frame_frequency: frame_specification.frequency,
        frame_allowed_frequency_leeway: frame_specification.allowed_frequency_leeway,
        allowed_missing_frames: frame_specification.allowed_missing_frames,
        allowed_missing_frames_period: frame_specification.allowed_missing_frames_period,
        required_on_time_frames: frame_specification.required_on_time_frames,
        missed_frame_count: 0,
        is_alive: false,
        on_time_frame_count: 0,
        last_missed_frame_at: now,
        system_last_frame_received_at: now
      }
    }
  end

  @impl true
  def handle_info(:validate_frequency, state) do
    now          = System.monotonic_time(:millisecond)
    allowed_diff = state.frame_frequency + state.frame_allowed_frequency_leeway
    frame_diff = cond do
      is_nil(state.frame_a_received_at) || is_nil(state.frame_b_received_at) -> allowed_diff + 1
      state.last_received_frame == :a -> state.frame_a_received_at - state.frame_b_received_at
      state.last_received_frame == :b -> state.frame_b_received_at - state.frame_a_received_at
    end
    system_diff = now - state.system_last_frame_received_at
    is_late      = frame_diff > allowed_diff || system_diff > 10 * allowed_diff
    is_alive     = state.is_alive
    state = case is_late do
      true -> %{state | last_missed_frame_at: now}
      false -> state
    end
    cond do
      is_alive && is_late && state.missed_frame_count >= state.allowed_missing_frames ->
        send_to_frame_handlers(state.frame_handlers, state.network_name, state.frame_name)
        {:noreply, %{state | is_alive: false}}
      is_alive && is_late ->
        {:noreply, %{state | on_time_frame_count: 0,  missed_frame_count: state.missed_frame_count + 1}}
      !is_alive && !is_late && state.on_time_frame_count >= state.required_on_time_frames ->
        {:noreply, %{state | on_time_frame_count: 0, is_alive: true}}
      !is_alive && !is_late ->
        {:noreply, %{state | on_time_frame_count: state.on_time_frame_count + 1,  missed_frame_count: 0}}
      is_alive && state.last_missed_frame_at + state.allowed_missing_frames_period < now ->
        {:noreply, %{state | missed_frame_count: 0}}
      true ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:handle_frame,  %Frame{reception_timestamp: reception_timestamp}}, state) do
    state = case state.last_received_frame do
      :a -> %{state | frame_b_received_at: reception_timestamp / 1000, last_received_frame: :b}
      :b -> %{state | frame_a_received_at: reception_timestamp / 1000, last_received_frame: :a}
    end
      {:noreply, %{state | system_last_frame_received_at: System.monotonic_time(:millisecond)}}
  end

  defp send_to_frame_handlers(frame_handlers, network_name, frame_name) do
    frame_handlers |> Enum.each(fn (frame_handler) ->
      Process.send(frame_handler, {:handle_missing_frame, network_name, frame_name}, [])
    end)
  end

  @impl true
  def handle_call({:subscribe, frame_handler}, _from, state) do
    ensure_frequency!(state)
    {:reply, :ok, %{state | frame_handlers: [frame_handler | state.frame_handlers]}}
  end

  def handle_call(:enable, _from, state) do
    case {state.frame_frequency, state.watching_timer}  do
      {nil, _} ->
        error = {:error, "No frequency was defined for frame #{state.frame_name}"}
        {:reply, error, state}
      {frequency, nil} ->
        {:ok, timer} = :timer.send_interval(frequency, :validate_frequency)
        {:reply, :ok, %{state | watching_timer: timer}}
      _ -> {:reply, :ok, state}
    end
  end

  def handle_call(:disable, _from, state) do
    case state.watching_timer do
      nil ->
        {:reply, :ok, state}
      watching_timer ->
        {:ok, _} = :timer.cancel(watching_timer)
        {:reply, :ok, %{state | watching_timer: nil}}
    end
  end

  def handle_call(:is_alive?, _from, state) do
      {:reply, {:ok, state.is_alive}, state}
  end

  def subscribe(network_name, frame_names, frame_handler) when is_list(frame_names) do
    frame_names |> Enum.each(
      fn (frame_name) ->
        subscribe(network_name, frame_name, frame_handler)
      end
    )
  end
  def subscribe(network_name, frame_name, frame_handler) do
    watcher = Interface.received_frame_watcher_process_name(network_name, frame_name)
    GenServer.call(watcher, {:subscribe, frame_handler})
  end

  def enable(network_name, frame_names) when is_list(frame_names) do
    frame_names |> Enum.each(
      fn (frame_name) ->
        enable(network_name, frame_name)
      end
    )
  end
  def enable(network_name, frame_name) do
    watcher = Interface.received_frame_watcher_process_name(network_name, frame_name)
    GenServer.call(watcher, :enable)
  end

  def disable(network_name, frame_names) when is_list(frame_names) do
    frame_names |> Enum.each(
      fn (frame_name) ->
        disable(network_name, frame_name)
      end
    )
  end
  def disable(network_name, frame_name) do
    watcher = Interface.received_frame_watcher_process_name(network_name, frame_name)
    GenServer.call(watcher, :disable)
  end

  def is_alive?(network_name, frame_name) do
    watcher = Interface.received_frame_watcher_process_name(network_name, frame_name)
    GenServer.call(watcher, :is_alive?)
  end

  defp ensure_frequency!(state) do
    if !state.frame_frequency do
      throw "[Yaml configuration error] Watched received frame '#{state.network_name}.#{state.frame_name}' is missing a frequency, please add it in the Yaml configuration."
    end
  end
end
