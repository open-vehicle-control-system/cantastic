defmodule Cantastic.SocketMessage do
  @moduledoc """
    `Cantastic.SocketMessage` is a `Struct` used to represent one **received** message on a libsocketcan socket.

    The attributes are the following:
    * `:raw` The raw bytes received on the CAN network.
    * `:reception_timestamp`  The `DateTime` at which the frame was received by the kernel.
  """

   defstruct [
    :raw,
    :reception_timestamp
  ]
end
