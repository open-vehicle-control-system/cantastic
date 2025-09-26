defmodule Cantastic.Receiver do
  @moduledoc """
    `Cantastic.Receiver` is a `GenServer` spawned per CAN network. It will then send the received `Cantastic.Frame` to all processes that subscribed to them.
  """

  use GenServer
  alias Cantastic.{Frame, Interface, ConfigurationStore, ReceivedFrameWatcher, Socket}
  require Logger

  @id_mask 0x1FFFFFFF

  def start_link(%{process_name: process_name} = args) do
    GenServer.start_link(__MODULE__, args, name: process_name)
  end

  @impl true
  def init(%{process_name:  _, frame_specifications: frame_specifications, socket: socket, network_name: network_name}) do
    receive_frame(200)
    Process.flag(:priority, :high)
    {:ok,
      %{
        network_name: network_name,
        socket: socket,
        frame_specifications: frame_specifications
      }
    }
  end

  @impl true
  def handle_info(:receive_frame, state) do
    {:ok, frame}        = receive_one_frame(state.network_name, state.socket)
    frame_specification = state.frame_specifications[frame.id]
    if not is_nil(frame_specification) do
      {:ok, frame} = Frame.interpret(frame, frame_specification)
      send_to_frame_handlers(frame_specification.frame_handlers, frame)
    end
    receive_frame()
    {:noreply, state}
  end

  defp receive_one_frame(network_name, socket) do
    {:ok, socket_message} = Socket.receive_message(socket)
    <<
      id_and_flags::little-integer-size(32),
      byte_number::little-integer-size(8),
      _unused2::binary-size(3),
      raw_data::binary-size(byte_number),
      _unused3::binary
    >> = socket_message.raw
    id = Bitwise.band(id_and_flags, @id_mask)

    frame = %Frame{
      id: id,
      network_name: network_name,
      byte_number: byte_number,
      raw_data: raw_data,
      created_at: DateTime.utc_now(),
      reception_timestamp: socket_message.reception_timestamp
    }
    {:ok, frame}
  end

  @impl true
  def handle_cast({:subscribe, frame_handler, frame_names, opts}, state) do
    frame_names = case frame_names do
      "*"   -> frame_names(state)
      [_|_] -> frame_names
    end
    subscribe_to_errors = opts[:errors] == true
    state = frame_names |> Enum.reduce(state, fn(frame_name, new_state) ->
      {:ok, frame_specification} = find_frame_specification_by_name(state.frame_specifications, frame_name)
      if subscribe_to_errors, do: :ok = ReceivedFrameWatcher.subscribe(state.network_name, frame_name, frame_handler)
      frame_handlers = [frame_handler | frame_specification.frame_handlers]
      put_in(new_state, [:frame_specifications, frame_specification.id, :frame_handlers], frame_handlers)
    end)
    {:noreply, state}
  end

  @doc false
  def find_frame_specification_by_name(frame_specifications, frame_name) do
    case frame_specifications |> Enum.find(fn ({_frame_id, f}) -> f.name == frame_name end) do
      {_frame_id, frame_specification} -> {:ok, frame_specification}
      nil ->
        spec = frame_specifications |> Map.values() |> List.first()
        network_name = Map.get(spec, :network_name, "UNKOWN_NETWORK")
        {:error, "Frame '#{frame_name}' not found for network '#{network_name}'"}
    end
  end

  defp send_to_frame_handlers(frame_handlers, frame) do
    frame_handlers |> Enum.each(fn (frame_handler) ->
      Process.send(frame_handler, {:handle_frame, frame}, [])
    end)
  end

  defp receive_frame(delay \\ 0) do
    Process.send_after(self(), :receive_frame, delay)
  end

  @doc """
  Subscribe `frame_handler :: pid()` to all frames received on a CAN network.

  Passing `%{errors: true}` as `opt` will also subscribe the `frame_handler` to `handle_missing_frame` events that are triggered when the related frames are not received during the expected timeframe on the CAN network. (see also `Cantastic.ReceivedFrameWatcher`)

  Returns `:ok`.

  ## Example

      iex> Cantastic.Receiver.subscribe(self(), :my_network)
      :ok

      iex> Cantastic.Receiver.subscribe(self(), :my_network, %{errors: true})
      :ok

  """
  def subscribe(frame_handler, opts \\ %{errors: false}) do
    ConfigurationStore.networks()|> Enum.each(fn (network) ->
      receiver =  Interface.receiver_process_name(network.network_name)
      GenServer.cast(receiver, {:subscribe, frame_handler, "*", opts})
    end)
  end

  @doc """
  Subscribe `frame_handler :: pid()` to one or multiple frames.

  Passing `%{errors: true}` as `opt` will also subscribe the `frame_handler` to `handle_missing_frame` events that are triggered when the related frames are not received during the expected timeframe on the CAN network. (see also `Cantastic.ReceivedFrameWatcher`)

  Returns `:ok`.

  ## Example

      iex> Cantastic.Receiver.subscribe(self(), :my_netowrk, "inverter_status")
      :ok

      iex> Cantastic.Receiver.subscribe(self(), :my_netowrk, "inverter_status", %{errors: true})
      :ok

      iex> Cantastic.Receiver.subscribe(self(), :my_netowrk, ["inverter_status", "inverter_temperatures"])
      :ok

  """
  def subscribe(frame_handler, network_name, frame_names, opts \\ %{errors: false})
  def subscribe(frame_handler, network_name, frame_names, opts) when is_list(frame_names) do
    receiver =  Interface.receiver_process_name(network_name)
    GenServer.cast(receiver, {:subscribe, frame_handler, frame_names, opts})
  end
  def subscribe(frame_handler, network_name, frame_names, opts) do
    subscribe(frame_handler, network_name, [frame_names], opts)
  end

  @doc false
  def frame_names(state) do
    state.frame_specifications |> Enum.map(fn({_frame_id, frame_specification}) ->
      frame_specification.name
    end)
  end
end
