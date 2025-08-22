defmodule Cantastic.OBD2.Request do
  use GenServer
  require Logger
  alias Cantastic.ISOTPRequest

  def start_link(%{process_name: process_name} = args) do
    GenServer.start_link(__MODULE__, args, name: process_name)
  end

  @impl true
  def init(%{process_name:  _, request_specification: request_specification}) do
    {:ok, socket} = Socket.bind_isotp(request_specification.can_interface, request_specification.request_frame_id, request_specification.response_frame_id, 0x0)
    {:ok,
      %{
        socket: socket,
        request_specification: request_specification,
        response_handlers: [],
        sending_timer: nil
      }
    }
  end

  @impl true
  def handle_cast(:send,  _from, state) do
    :ok = Socket.send(socket, raw_data)
    {:ok, response} = Socket.receive_message(state.socket)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:enable, state) do
    case state.sending_timer do
      nil ->
        {:ok, timer} = :timer.send_interval(state.request_specification.frequency, :send_frame)
        {:noreply, %{state | sending_timer: timer}}
      _ ->
        {:noreply, state}
    end
  end

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
  def handle_cast({:subscribe, response_handler}, state) do
    response_handlers = [response_handler | state.response_handlers]
    {:noreply, %{state | response_handlers: response_handlers}}
  end

  defp send_to_response_handlers(response_handlers, response) do
    response_handlers |> Enum.each(fn (response_handler) ->
      Process.send(response_handler, {:handle_obd2_response, response}, [])
    end)
  end

  defp receive_frame(delay \\ 0) do
    Process.send_after(self(), :receive_frame, delay)
  end

  def subscribe(response_handler, opts \\ %{errors: false}) do
    ConfigurationStore.networks()|> Enum.each(fn (network) ->
      receiver =  Interface.receiver_process_name(network.network_name)
      GenServer.cast(receiver, {:subscribe, frame_handler, "*", opts})
    end)
  end

  def subscribe(frame_handler, network_name, frame_names, opts \\ %{errors: false})
  def subscribe(frame_handler, network_name, frame_names, opts) when is_list(frame_names) do
    receiver =  Interface.receiver_process_name(network_name)
    GenServer.cast(receiver, {:subscribe, frame_handler, frame_names, opts})
  end
  def subscribe(frame_handler, network_name, frame_names, opts) do
    subscribe(frame_handler, network_name, [frame_names], opts)
  end
end
