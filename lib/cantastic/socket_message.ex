defmodule Cantastic.SocketMessage do
  @moduledoc """
    `Cantastic.SocketMessage` is a `Struct` used to represent one **received** message on a libsocketcan socket.

    The attributes are the following:
    * `:raw` The raw bytes received on the CAN network.
    * `:reception_timestamp`  When the kernel received the frame, in microseconds since the Unix epoch. It follows the wall clock, so it can step when the system time is set: measure intervals with `System.monotonic_time/1` instead.
  """

  defstruct [
    :raw,
    :reception_timestamp
  ]
end
