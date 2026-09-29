defmodule Cantastic.Receiver do
  @moduledoc """
    `Cantastic.Receiver` is a `GenServer` spawned per CAN network. It will then send the received `Cantastic.Frame` to all processes that subscribed to them.
  """

  use GenServer

  alias Cantastic.{
    Frame,
    FrameSpecification,
    Interface,
    ConfigurationStore,
    ReceivedFrameWatcher,
    Socket
  }

  require Logger

  @id_mask 0x1FFFFFFF
  @eff_flag 0x80000000

  def start_link(%{process_name: process_name} = args) do
    GenServer.start_link(__MODULE__, args, name: process_name)
  end

  @impl true
  def init(%{
        process_name: _,
        frame_specifications: frame_specifications,
        socket: socket,
        network_name: network_name
      }) do
    # The receiver spends its time blocked in the socket read, so it cannot
    # answer calls. Subscribers validate frame names against this list in
    # their own process instead.
    :persistent_term.put(
      declared_frame_names_key(network_name),
      frame_specifications |> Map.values() |> Enum.map(& &1.name)
    )

    receive_frame(200)
    Process.flag(:priority, :high)

    {:ok,
     %{
       network_name: network_name,
       socket: socket,
       frame_specifications: frame_specifications
     }}
  end

  @impl true
  def handle_info(:receive_frame, state) do
    {:ok, frame} = receive_one_frame(state.network_name, state.socket)
    frame_specification = state.frame_specifications[FrameSpecification.can_id(frame)]

    if not is_nil(frame_specification) do
      case Frame.interpret(frame, frame_specification) do
        {:ok, frame} ->
          send_to_frame_handlers(frame_specification.frame_handlers, frame)

        {:error, reason} ->
          # A single frame that does not fit its specification -- a short
          # DLC, bus noise, a foreign device sharing an id -- must not
          # crash the receiver, and with it every watcher and consumer on
          # this network. Skip it, and name it so the mismatch is findable.
          Logger.warning(
            "#{state.network_name}: dropped 0x#{Frame.format_id(frame)} " <>
              "(#{byte_size(frame.raw_data)} data bytes) -- cannot decode against " <>
              "'#{frame_specification.name}': #{inspect(reason)}"
          )
      end
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
    extended = Bitwise.band(id_and_flags, @eff_flag) != 0

    frame = %Frame{
      id: id,
      extended: extended,
      network_name: network_name,
      byte_number: byte_number,
      raw_data: raw_data,
      created_at: DateTime.utc_now(),
      reception_timestamp: socket_message.reception_timestamp
    }

    {:ok, frame}
  end

  @impl true
  def handle_cast({:subscribe, frame_handler, frame_names}, state) do
    frame_names =
      case frame_names do
        "*" -> frame_names(state)
        _ -> frame_names
      end

    state =
      frame_names
      |> Enum.reduce(state, fn frame_name, new_state ->
        case find_frame_specification_by_name(new_state.frame_specifications, frame_name) do
          {:ok, frame_specification} ->
            frame_handlers = [frame_handler | frame_specification.frame_handlers]

            put_in(
              new_state,
              [
                :frame_specifications,
                FrameSpecification.can_id(frame_specification),
                :frame_handlers
              ],
              frame_handlers
            )

          {:error, reason} ->
            Logger.warning("#{reason}, subscription of #{inspect(frame_handler)} ignored")
            new_state
        end
      end)

    {:noreply, state}
  end

  @doc false
  def find_frame_specification_by_name(frame_specifications, frame_name) do
    case frame_specifications |> Enum.find(fn {_frame_id, f} -> f.name == frame_name end) do
      {_frame_id, frame_specification} ->
        {:ok, frame_specification}

      nil ->
        network_name =
          case frame_specifications |> Map.values() |> List.first() do
            nil -> "UNKNOWN_NETWORK"
            spec -> spec.network_name
          end

        {:error, "Frame '#{frame_name}' not found for network '#{network_name}'"}
    end
  end

  defp send_to_frame_handlers(frame_handlers, frame) do
    frame_handlers
    |> Enum.each(fn frame_handler ->
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

      iex> Cantastic.Receiver.subscribe(self())
      :ok

      iex> Cantastic.Receiver.subscribe(self(), %{errors: true})
      :ok

  """
  def subscribe(frame_handler, opts \\ %{errors: false}) do
    ConfigurationStore.networks()
    |> Enum.each(fn network ->
      case declared_frame_names(network.network_name) do
        nil -> cast_subscription(frame_handler, network.network_name, "*")
        frame_names -> subscribe(frame_handler, network.network_name, frame_names, opts)
      end
    end)
  end

  @doc """
  Subscribe `frame_handler :: pid()` to one or multiple frames.

  Passing `%{errors: true}` as `opt` will also subscribe the `frame_handler` to `handle_missing_frame` events that are triggered when the related frames are not received during the expected timeframe on the CAN network. (see also `Cantastic.ReceivedFrameWatcher`)

  Returns `:ok`, or `{:error, reason}` without subscribing to any frame when one of `frame_names` is not declared in the network's `received_frames`.

  ## Example

      iex> Cantastic.Receiver.subscribe(self(), :my_network, "inverter_status")
      :ok

      iex> Cantastic.Receiver.subscribe(self(), :my_network, "inverter_status", %{errors: true})
      :ok

      iex> Cantastic.Receiver.subscribe(self(), :my_network, ["inverter_status", "inverter_temperatures"])
      :ok

      iex> Cantastic.Receiver.subscribe(self(), :my_network, "not_a_declared_frame")
      {:error, "Frame(s) 'not_a_declared_frame' not found for network 'my_network'"}

  """
  def subscribe(frame_handler, network_name, frame_names, opts \\ %{errors: false})

  def subscribe(frame_handler, network_name, frame_names, opts) when is_list(frame_names) do
    frame_names = Enum.uniq(frame_names)

    case declared_frame_names(network_name) do
      # No receiver has started for this network.
      nil ->
        cast_subscription(frame_handler, network_name, frame_names)

      declared_frame_names ->
        case frame_names -- declared_frame_names do
          [] ->
            if opts[:errors] == true,
              do: :ok = ReceivedFrameWatcher.subscribe(network_name, frame_names, frame_handler)

            cast_subscription(frame_handler, network_name, frame_names)

          undeclared_frame_names ->
            reason =
              "Frame(s) '#{Enum.join(undeclared_frame_names, "', '")}' not found for network '#{network_name}'"

            Logger.error("#{reason}, subscription of #{inspect(frame_handler)} refused")
            {:error, reason}
        end
    end
  end

  def subscribe(frame_handler, network_name, frame_names, opts) do
    subscribe(frame_handler, network_name, [frame_names], opts)
  end

  defp cast_subscription(frame_handler, network_name, frame_names) do
    receiver = Interface.receiver_process_name(network_name)
    GenServer.cast(receiver, {:subscribe, frame_handler, frame_names})
  end

  defp declared_frame_names(network_name) do
    :persistent_term.get(declared_frame_names_key(network_name), nil)
  end

  defp declared_frame_names_key(network_name), do: {__MODULE__, network_name}

  @doc false
  def frame_names(state) do
    state.frame_specifications
    |> Enum.map(fn {_frame_id, frame_specification} ->
      frame_specification.name
    end)
  end
end
