defmodule Cantastic.Emitter do
  @moduledoc """
    `Cantastic.Emitter` is a `GenServer` used to emit CAN frames at the frequency defined in your YAML configuration file.

    There is one Emitter process started per emitted frame on a CAN network.

    Here is an example on how to configure a simple emitter and start emitting frames immediately:

    ```
    :ok = Emitter.configure(:network_name, "my_frame", %{
      parameters_builder_function: :default,
      initial_data: %{
        "gear" => "drive"
      },
      enable: true
    })
    ```

  """
  use GenServer
  alias Cantastic.{Interface, Frame, Socket}

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

  ## Example

      iex> Cantastic.Emitter.send_frame(:network_name, "my_frame")
      :ok

  """
  def send_frame(network_name, frame_name) do
    emitter = Interface.emitter_process_name(network_name, frame_name)
    Process.send(emitter, :send_frame, [])
  end

  def get(emitter, fun, timeout \\ 5000) when is_function(fun, 1) do
    GenServer.call(emitter, {:get, fun}, timeout)
  end

  @doc """
  Update the emitter's data.

  It allows you to modify the signal's values to sent on the bus. Your function receives the `data` map and must return the updated version.

  Returns: `:ok`

  ## Examples

      iex> Cantastic.Emitter.update(:network_name, "my_frame", fn(data) ->
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

  The function will receive the Emitter's `data` as a parameter and should return `{:ok, parameters, data}`, where `parameters` is a map containing a value for each signal of the emitter's frame.

  If all you need is to send the current values stored in data, you can simply pass `:default` as parameters_builder_function, which is equivalent to `fn (data) -> {:ok, data, data}`.

  You can start to emit immediately by setting the `enable` key to `true`.

  The `initial_data` key allows you to provide the initial values.

  Returns: `:ok`

  ## Examples

      iex> Cantastic.Emitter.configure(:network_name, %{
        parameters_builder_function: fn (data) ->
          {
            :ok,
            %{"counter" => data["counter"], "gear" => data["gear"]},
            %{data | "counter" => data["counter"] + 1}
          }
        end,
        initial_data: %{"counter" => 0, "gear" => "drive"}
      })
      :ok

      iex> Cantastic.Emitter.configure(:network_name, %{
        parameters_builder_function: :default,
        initial_data: %{"gear" => "drive"},
        enable: true
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

      iex> Cantastic.Emitter.disable(:drive_can, "engine_status")
      :ok

      iex> Cantastic.Emitter.disable(:drive_can, ["engine_status", "throttle"])
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

  @doc """
  Forward a frame to another CAN network

  Returns: `:ok`

  ## Examples

      iex> Cantastic.Emitter.forward(:my_network, frame)
      :ok
  """
  def forward(network_name, frame) do
    emitter = Interface.emitter_process_name(network_name, frame.name)
    GenServer.cast(emitter, {:forward, frame})
  end

  defp send_raw(state, raw_frame) do
    case Socket.send(state.socket, raw_frame) do
      :ok -> state
      {:error, reason} -> %{state | failed_sending_count: state.failed_sending_count + 1, last_sending_error_reason: reason}
    end
  end
end
