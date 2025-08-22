defmodule Cantastic.OBD2.Request do
  use GenServer
  require Logger
  alias Cantastic.Socket
  alias Cantastic.OBD2.{Response}

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
        sending_timer: nil,
        raw_request: compute_raw_request(request_specification)
      }
    }
  end

  @impl true
  def handle_cast(:send_request,  _from, state) do
    with  :ok <- Socket.send(state.socket, state.raw_request),
          {:ok, raw_response} <- Socket.receive_message(state.socket),
          {:ok, response}     <- Response.interpret(state.request_specification, raw_response)
    do
      send_to_response_handlers(state.response_handlers, response)
      {:noreply, state}
    else
      {:error, error} -> {:error, error}
    end
  end

  @impl true
  def handle_cast(:enable, state) do
    case state.sending_timer do
      nil ->
        {:ok, timer} = :timer.send_interval(state.request_specification.frequency, :send_request)
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

  def subscribe(response_handler, network_name, request_name) do
    request =  Interface.obd2_request_process_name(network_name, request_name)
    GenServer.cast(request, {:subscribe, response_handler})
  end

  defp send_to_response_handlers(response_handlers, response) do
    response_handlers |> Enum.each(fn (response_handler) ->
      Process.send(response_handler, {:handle_obd2_response, response}, [])
    end)
  end

  defp compute_raw_request(request_specification) do
    acc         = <<request_specification.mode::integer-size(8)>>
    raw_request = request_specification.parameter_specifications |> Enum.reduce(acc, fn(parameter_specification, acc) ->
       <<acc::bitstring, parameter_specification.id::integer-size(8)>>
    end)
    {:ok, raw_request}
  end

end
