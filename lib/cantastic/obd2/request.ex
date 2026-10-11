defmodule Cantastic.OBD2.Request do
  @moduledoc """
    `Cantastic.OBD2.Request` is a `GenServer` used to emit OBD2 requests at the frequency defined in your YAML configuration file.

    There is one process started per OBD2 request defined in your YAML file.

    Here is an example on how to subscribe to one OBD2 request and start emitting it:

    ```
    :ok = OBD2.Request.subscribe(self(), :obd2, "current_speed_and_rotation_per_minute")
    :ok = OBD2.Request.enable(:obd2, "current_speed_and_rotation_per_minute")
    ```
  """

  use GenServer
  require Logger
  alias Cantastic.{Interface, Socket, Ticker}
  alias Cantastic.OBD2.{Codec, Response}

  @response_timeout_ms 1_000

  def start_link(%{process_name: process_name} = args) do
    GenServer.start_link(__MODULE__, args, name: process_name)
  end

  @impl true
  def init(%{process_name: _, request_specification: request_specification}) do
    {:ok, socket} =
      Socket.bind_isotp(
        request_specification.can_interface,
        request_specification.request_frame_id,
        request_specification.response_frame_id,
        0x0
      )

    {:ok, raw_request} = Codec.encode_request(request_specification)

    {:ok,
     %{
       socket: socket,
       request_specification: request_specification,
       response_handlers: [],
       ticker: nil,
       raw_request: raw_request
     }}
  end

  @impl true
  def handle_info({:tick, ref}, %{ticker: %Ticker{ref: ref}} = state) do
    send_request(state)
    {:noreply, %{state | ticker: Ticker.next(state.ticker)}}
  end

  # A tick of a ticker cancelled by disable/2.
  def handle_info({:tick, _stale_tick_ref}, state) do
    {:noreply, state}
  end

  def handle_info(:send_request, state) do
    send_request(state)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:enable, state) do
    case state.ticker do
      nil ->
        # The first tick only fires after a full period, so the first request
        # goes out now: a request enabled briefly (or with a long frequency)
        # would otherwise never be sent.
        send(self(), :send_request)
        {:noreply, %{state | ticker: Ticker.start(state.request_specification.frequency)}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_cast(:disable, state) do
    {:noreply, %{state | ticker: Ticker.cancel(state.ticker)}}
  end

  @impl true
  def handle_cast({:subscribe, response_handler}, state) do
    response_handlers = [response_handler | state.response_handlers]
    {:noreply, %{state | response_handlers: response_handlers}}
  end

  defp send_request(state) do
    with :ok <- Socket.send(state.socket, state.raw_request),
         {:ok, socket_message} <- Socket.receive_message(state.socket, @response_timeout_ms),
         {:ok, response} <- Response.interpret(state.request_specification, socket_message) do
      send_to_response_handlers(state.response_handlers, response)
    else
      {:error, error} -> send_to_error_handlers(state.response_handlers, error)
    end
  end

  defp send_to_response_handlers(response_handlers, response) do
    response_handlers
    |> Enum.each(fn response_handler ->
      Process.send(response_handler, {:handle_obd2_response, response}, [])
    end)
  end

  defp send_to_error_handlers(response_handlers, error) do
    response_handlers
    |> Enum.each(fn response_handler ->
      Process.send(response_handler, {:handle_obd2_error, error}, [])
    end)
  end

  @doc """
  Enable the OBD2 request(s), the request(s) is/are then emitted on the bus once immediately, then at the predefined frequency.

  Each request waits up to #{@response_timeout_ms} ms for its response, then reports `{:handle_obd2_error, :timeout}`. A request that takes longer than the period skips the periods it overran instead of queueing them.

  Returns: `:ok`

  ## Examples

    iex> Cantastic.OBD2.Request.enable(:obd2, "current_speed_and_rpm")
    :ok

    iex> Cantastic.OBD2.Request.enable(:obd2, ["current_speed_and_rpm", "throttle_status"])
    :ok
  """
  def enable(network_name, request_names) when is_list(request_names) do
    request_names
    |> Enum.each(fn request_name ->
      enable(network_name, request_name)
    end)
  end

  def enable(network_name, request_name) do
    request = Interface.obd2_request_process_name(network_name, request_name)
    GenServer.cast(request, :enable)
  end

  @doc """
  Disable the OBD2 request(s), the requests is/are then not emitted on the bus anymore.

  Returns: `:ok`

  ## Examples

    iex> Cantastic.OBD2.Request.disable(:obd2, "current_speed_and_rpm")
    :ok

    iex> Cantastic.OBD2.Request.disable(:obd2, ["current_speed_and_rpm", "current_speed_and_rpm"])
    :ok
  """
  def disable(network_name, request_names) when is_list(request_names) do
    request_names
    |> Enum.each(fn request_name ->
      disable(network_name, request_name)
    end)
  end

  def disable(network_name, request_name) do
    request = Interface.obd2_request_process_name(network_name, request_name)
    GenServer.cast(request, :disable)
  end

  @doc """
  Subscribe `response_handler :: pid()` to one OBD2 request.

  Returns `:ok`.

  ## Example

      iex> Cantastic.OBD2.Request.subscribe(self(), :my_network, "current_speed_and_rpm")
      :ok
  """
  def subscribe(response_handler, network_name, request_name) do
    request = Interface.obd2_request_process_name(network_name, request_name)
    GenServer.cast(request, {:subscribe, response_handler})
  end
end
