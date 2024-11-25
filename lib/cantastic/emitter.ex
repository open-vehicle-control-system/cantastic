defmodule Cantastic.Emitter do
  @moduledoc """
    `Cantastic.Emitter` is a process used to emit frames at the frequency defined in your Yaml configuration file.

    There is one Emitter process started per frame to be emitted.

  """
  use GenServer
  alias Cantastic.{Interface, Frame}

  @sending_timeout 100

  def start_link(%{process_name: process_name} = args) do
    GenServer.start_link(__MODULE__, args, name: process_name)
  end

  @impl true
  def init(%{process_name:  _, frame_specification: frame_specification, socket: socket, network_name: network_name}) do
    {:ok,
      %{
        socket: socket,
        network_name: network_name,
        parameters_builder_function: :default,
        sending_timer: nil,
        data: %{},
        frequency: frame_specification.frequency,
        frame_specification: frame_specification,
        failed_sending_count: 0,
        last_sending_error_reason: nil
      }
    }
  end

  @impl true
  def handle_info(:send_frame, state) do
    {:ok, parameters, data} = state.parameters_builder_function.(state.data)
    {:ok, raw_frame}        = Frame.build_raw(state.frame_specification, parameters)
    state                   = send_raw(state, raw_frame)
    {:noreply, %{state | data: data}}
  end

  @impl true
  def handle_cast({:forward, frame}, state) do
    raw_frame = Frame.to_raw(frame)
    state     = send_raw(state, raw_frame)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:enable, state) do
    case state.sending_timer do
      nil ->
        {:ok, timer} = :timer.send_interval(state.frequency, :send_frame)
        {:noreply, %{state | sending_timer: timer}}
      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:disable, state) do
    case state.sending_timer do
      nil ->
        {:noreply, state}
      sending_timer ->
        {:ok, _} = :timer.cancel(sending_timer)
        {:noreply, %{state | sending_timer: nil}}
    end
  end

  @impl true
  def handle_call({:get, fun}, _from, state) do
    {:reply, fun.(state.data), state}
  end

  @impl true
  def handle_call({:update, fun}, _from, state) do
    data = fun.(state.data)
    {:reply, :ok, %{state | data: data}}
  end

  @impl true
  def handle_call({:configure, initialization_args}, _from, state) do
    parameters_builder_function = case initialization_args.parameters_builder_function do
      :default -> fn (data) -> {:ok, data, data} end
      function when is_function(function) -> function
    end

    state = state
    |> Map.put(:parameters_builder_function, parameters_builder_function)
    |> Map.put(:data, initialization_args.initial_data)

    if Map.get(initialization_args, :enable, false), do: GenServer.cast(self(), :enable)
    {:reply, :ok, state}
  end

  @doc """
  Send the frame once.
  `configure/2` has to be called before the emitter can start emitting on the bus.

  Returns `:ok`.
  """
  def send_frame(emitter) do
    Process.send_after(emitter, :send_frame, 0)
  end

  def get(emitter, fun, timeout \\ 5000) when is_function(fun, 1) do
    GenServer.call(emitter, {:get, fun}, timeout)
  end

  @doc """
  Update the emitter's state.

  It allows you to modify the signal's values sent on the bus. Your function receive the `data` map and must return the updated version.

  Returns: `:ok`

  ## Examples

    iex> Cantastic.Emitter.update(:drive_can, "vms_status", fn(data) ->
      %{data | gear: "parking"}
    end)
    :ok
  """
  def update(network_name, frame_name, fun, timeout \\ 5000) when is_function(fun, 1) do
    emitter =  Interface.emitter_process_name(network_name, frame_name)
    GenServer.call(emitter, {:update, fun}, timeout)
  end

  @doc """
  Configure the emitter, it has to be called before `enable/2`.

  You must provide a `parameters_builder_function` that will be used by the emitter to compute the actual `Cantastic.Signal` value(s).
  The function will receive the Emitter's `state` as a parameter and should return `{:ok, parameters, state}`, where `parameters` is a map containing a value for each signal of the emitter's frame.
  The `initial_data` key allows you to provide some initial values for the emitter's `state.data`.

  Returns: `:ok`

  ## Examples

    iex> Cantastic.Emitter.configure(:drive_can, %{
      parameters_builder_function: fn (data) -> {:ok, %{"counter" => data["counter"], "gear" => data["gear"]}, %{data | "counter" => data["counter"] + 1}} end,
      initial_data: %{"counter" => 0, "gear" => "drive"}
    })
    :ok
  """
  def configure(network_name, frame_name, initialization_args) do
    emitter =  Interface.emitter_process_name(network_name, frame_name)
    GenServer.call(emitter, {:configure, initialization_args})
  end

  @doc """
  Enable the emitter(s), the frame(s) is/are then emitted on the bus at the predefined frequency.

  Returns: `:ok`

  ## Examples

    iex> Cantastic.Emitter.enable(:drive_can, "engine_status")
    :ok

    iex> Cantastic.Emitter.enable(:drive_can, ["engine_status", "throttle"])
    :ok
  """
  def enable(network_name, frame_names) when is_list(frame_names) do
    frame_names |> Enum.each(
      fn (frame_name) ->
        enable(network_name, frame_name)
      end
    )
  end
  def enable(network_name, frame_name) do
    emitter = Interface.emitter_process_name(network_name, frame_name)
    GenServer.cast(emitter, :enable)
  end

  @doc """
  Disable the emitter(s), the frame is/are then not emitted on the bus anymore.

  Returns: `:ok`

  ## Examples

    iex> Cantastic.Emitter.enable(:drive_can, "engine_status")
    :ok

    iex> Cantastic.Emitter.enable(:drive_can, ["engine_status", "throttle"])
    :ok
  """
  def disable(network_name, frame_names) when is_list(frame_names) do
    frame_names |> Enum.each(
      fn (frame_name) ->
        disable(network_name, frame_name)
      end
    )
  end
  def disable(network_name, frame_name) do
    emitter = Interface.emitter_process_name(network_name, frame_name)
    GenServer.cast(emitter, :disable)
  end

  def forward(network_name, frame) do
    emitter = Interface.emitter_process_name(network_name, frame.name)
    GenServer.cast(emitter, {:forward, frame})
  end

  defp send_raw(state, raw_frame) do
    case :socket.send(state.socket, raw_frame, @sending_timeout) do
      :ok -> state
      {:error, reason} -> %{state | failed_sending_count: state.failed_sending_count + 1, last_sending_error_reason: reason}
    end
  end
end
