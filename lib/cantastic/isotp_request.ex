defmodule Cantastic.ISOTPRequest do
  use GenServer
  require Logger
  alias Cantastic.Socket

  def start_link(%{process_name: process_name} = args) do
    GenServer.start_link(__MODULE__, args, name: process_name)
  end

  @impl true
  def init(%{process_name:  _, can_interface: can_interface, request_frame_id: request_frame_id, response_frame_id: response_frame_id}) do
    {:ok, socket} = Socket.bind_isotp(can_interface, request_frame_id, response_frame_id)
    {:ok,
      %{
        socket: socket,
        request_frame_id: request_frame_id,
        response_frame_id: response_frame_id
      }
    }
  end

  @impl true
  def handle_call({:send, raw_data},  _from, state) do
    :ok = Socket.send(state.socket, raw_data)
    {:ok, response} = Socket.receive_message(state.socket)

    {:reply, {:ok, response}, state}
  end

  def send(process, raw_data) do
    GenServer.call(process, {:send, raw_data})
  end
end
