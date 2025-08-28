defmodule Cantastic.OBD2.Request do
  use GenServer
  require Logger
  alias Cantastic.{Interface, Socket}
  alias Cantastic.OBD2.{Response}

  def start_link(%{process_name: process_name} = args) do
    GenServer.start_link(__MODULE__, args, name: process_name)
  end

  @impl true
  def init(%{process_name:  _, request_specification: request_specification}) do
    {:ok, socket}      = Socket.bind_isotp(request_specification.can_interface, request_specification.request_frame_id, request_specification.response_frame_id, 0x0)
    {:ok, raw_request} = compute_raw_request(request_specification)
    {:ok,
      %{
        socket: socket,
        request_specification: request_specification,
        response_handlers: [],
        sending_timer: nil,
        raw_request: raw_request
      }
    }
  end

  @impl true
  def handle_info(:send_request, state) do
    with  :ok                   <- Socket.send(state.socket, state.raw_request),
          {:ok, socket_message} <- Socket.receive_message(state.socket),
          {:ok, response}       <- Response.interpret(state.request_specification, socket_message)
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

  defp send_to_response_handlers(response_handlers, response) do
    response_handlers |> Enum.each(fn (response_handler) ->
      Process.send(response_handler, {:handle_obd2_response, response}, [])
    end)
  end

  defp compute_raw_request(request_specification) do
      acc         = <<request_specification.mode::big-integer-size(8)>>
      raw_request = request_specification.parameter_specifications |> Enum.reduce(acc, fn(parameter_specification, acc) ->
       <<acc::bitstring, parameter_specification.id::integer-size(8)>>
    end)
    {:ok, raw_request}
  end

  @doc """
  Enable the OBD2 request(s), the request(s) is/are then emitted on the bus at the predefined frequency.

  Returns: `:ok`

  ## Examples

    iex> Cantastic.OBD2.Request.enable(:obd2, "current_speed_and_rpm")
    :ok

    iex> Cantastic.OBD2.Request.enable(:obd2, ["current_speed_and_rpm", "throttle_status"])
    :ok
  """
  def enable(network_name, request_names) when is_list(request_names) do
    request_names |> Enum.each(
      fn (request_name) ->
        enable(network_name, request_name)
      end
    )
  end
  def enable(network_name, request_name) do
    request = Interface.obd2_request_process_name(network_name, request_name)
    GenServer.cast(request, :enable)
  end

  @doc """
  Disable the emitter(s), the frame is/are then not emitted on the bus anymore.

  Returns: `:ok`

  ## Examples

    iex> Cantastic.OBD2.Request.enable(:obd2, "current_speed_and_rpm")
    :ok

    iex> Cantastic.OBD2.Request.enable(:obd2, ["current_speed_and_rpm", "current_speed_and_rpm"])
    :ok
  """
  def disable(network_name, request_names) when is_list(request_names) do
    request_names |> Enum.each(
      fn (request_name) ->
        disable(network_name, request_name)
      end
    )
  end
  def disable(network_name, request_name) do
    request = Interface.obd2_request_process_name(network_name, request_name)
    GenServer.cast(request, :disable)
  end

  def subscribe(response_handler, network_name, request_name) do
    request =  Interface.obd2_request_process_name(network_name, request_name)
    GenServer.cast(request, {:subscribe, response_handler})
  end
end
