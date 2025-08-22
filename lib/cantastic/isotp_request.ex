defmodule Cantastic.ISOTPRequest do
  alias Cantastic.Socket

  def bind_socket(can_interface, request_frame_id, response_frame_id, tx_padding) do
    Socket.bind_isotp(can_interface, request_frame_id, response_frame_id, tx_padding)
  end

  def send(socket, raw_data) do
    :ok = Socket.send(socket, raw_data)
    Socket.receive_message(state.socket)
  end
end
