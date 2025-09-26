defmodule Cantastic.Socket do
  @moduledoc """
    `Cantastic.Socket` is a utility module allowing to interact with the libsocketcan Linux sockets.

    If you do not want to use Cantastic's declarative way of defining frames, you could use this module to interact directly with the CAN Bus.
  """

  require Logger
  alias Cantastic.SocketMessage

  # Source: https://github.com/linux-can/linux/blob/56cfd2507d3e720f4b1dbf9513e00680516a0826/include/linux/socket.h#L193
  @protocol_family 29 # PF_CAN == AF_CAN

  # Source: https://www.erlang.org/docs/26/man/socket#type-type
  @protocol_types %{
    raw: :raw,
    isotp: :dgram
  }

  # Source https://github.com/linux-can/linux/blob/56cfd2507d3e720f4b1dbf9513e00680516a0826/include/uapi/linux/can.h#L153
  @protocols %{
    raw: 1,
    isotp: 6
  }

  # Source: https://github.com/linux-can/can-utils/blob/6b46063eee805e0e680833da02fc16f15b92bf1e/include/linux/can.h#L239C9-L239C25
  @sol_can_base 100
  #Source: https://github.com/linux-can/can-utils/blob/6b46063eee805e0e680833da02fc16f15b92bf1e/include/linux/can/isotp.h#L50
  @sol_can_isotp @sol_can_base + @protocols[:isotp]

  # Source: https://github.com/linux-can/can-utils/blob/6b46063eee805e0e680833da02fc16f15b92bf1e/include/linux/can/isotp.h#L54
  @can_isotp_opts  1

  # Source: https://github.com/linux-can/can-utils/blob/6b46063eee805e0e680833da02fc16f15b92bf1e/include/linux/can/isotp.h#L125
  @can_isotp_tx_padding 0x0004

  # Source: https://github.com/torvalds/linux/blob/0cc53520e68bea7fb80fdc6bdf8d226d1b6a98d9/include/uapi/linux/sockios.h#L153
  @timestamp_flags 0x8906 # SIOCGSTAMP: 0x8906 - SIOCGSTAMPNS: 0x8907 - SIOCSHWTSTAMP": 0x89b0 - SIOCGHWTSTAMP: 0x89b1

  @sending_timeout 100

  @doc """
  Bind the CAN socket in RAW mode on the `interface`.

  Returns: `{:ok, socket}`

  ## Examples

      iex> Cantastic.Socket.bind_raw("can0")
      {:ok, socket}
  """
  def bind_raw(interface) do
    with {:ok, socket} <- open(:raw),
          :ok          <- request_hardware_timestamping(socket),
         {:ok, socket} <- bind(socket, interface)
    do
      {:ok, socket}
    else
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Bind the CAN socket in ISOTP mode on the `interface`, you have to provide the  `request_frame_id`, `response_frame_id` and an optional  `tx_padding`.

  Returns: `{:ok, socket}`

  ## Examples

      iex> Cantastic.Socket.bind_isotp("can0", 0x799, 0x771, 0x0)
      {:ok, socket}
  """
  def bind_isotp(interface, request_frame_id, response_frame_id, tx_padding \\ nil) do
    with {:ok, socket} <- open(:isotp),
         :ok           <- request_hardware_timestamping(socket),
         :ok           <- request_isotp_padding(socket, tx_padding),
         {:ok, socket} <- bind(socket, interface, request_frame_id, response_frame_id)
    do
      {:ok, socket}
    else
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Send one `raw` frame on the `socket`.

  Returns: `:ok`

  ## Examples

      iex> Cantastic.Socket.send(socket, <<....>>)
      :ok
  """
  def send(socket, raw) do
    case :socket.send(socket, raw, @sending_timeout) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Receive one `message` frame on the `socket`. This function will block indefinitely until a message is received.

  Returns: `{:ok, %Cantastic.SocketMessage{} = message}`

  ## Examples

      iex> Cantastic.Socket.receive_message(socket)
      {:ok, %Cantastic.SocketMessage{} = message}
  """
  def receive_message(socket) do
    [raw, timestamp_seconds, timestamp_usec] = case :socket.recvmsg(socket) do
      {:ok, %{
        iov: [raw],
        ctrl: [%{type: :timestamp, value: %{sec: timestamp_seconds, usec: timestamp_usec}}]
      }} -> [raw, timestamp_seconds, timestamp_usec]
      {:ok, %{
        iov: [raw],
        ctrl: [_, %{type: :timestamp, value: %{sec: timestamp_seconds, usec: timestamp_usec}}]
      }} -> [raw, timestamp_seconds, timestamp_usec]
    end

    reception_timestamp = timestamp_seconds * 1_000_000 + timestamp_usec # TODO return timestamp
    message = %SocketMessage{raw: raw, reception_timestamp: reception_timestamp}
    {:ok, message}
  end

  defp bind(socket, interface, request_frame_id \\ 0, response_frame_id \\ 0) do
    with {:ok, address} <- build_raw_address(socket, interface, request_frame_id, response_frame_id),
         :ok            <- :socket.bind(socket, %{:family => @protocol_family, :addr => address})
    do
      {:ok, socket}
    else
      {:error, :enodev} -> {:error, "CAN interface not found by libsocketcan. Make sure it is configured and enabled first with '$ ip link show'"}
      {:error, error} -> {:error, error}
    end
  end

  defp open(protocol) do
    :socket.open(@protocol_family, @protocol_types[protocol], @protocols[protocol])
  end

  defp request_hardware_timestamping(socket) do
    :socket.setopt_native(socket, {:socket, @protocol_family}, @timestamp_flags)
  end

  defp request_isotp_padding(socket, tx_padding) do
    # Source: https://docs.kernel.org/networking/iso15765-2.html#iso-tp-socket-options
    case tx_padding do
      nil ->
        :ok
      _ ->
        flags          = @can_isotp_tx_padding
        iso_tp_options = <<
          flags::size(32)-little,
          0::size(32)-little,
          0::size(8)-little,
          tx_padding::size(8)-little,
          0::size(8)-little,
          0::size(8)-little
        >>
        :socket.setopt_native(socket, {@sol_can_isotp, @can_isotp_opts}, iso_tp_options)
    end

  end

  defp build_raw_address(socket, interface, request_frame_id, response_frame_id) do
    charlist_interface = interface |> String.to_charlist()
    case :socket.ioctl(socket, :gifindex, charlist_interface) do
      {:ok, ifindex} ->
        # Source: https://elixirforum.com/t/erlang-socket-module-for-socketcan-on-nerves-device/57294/6
        address = <<
          0::size(16)-little,
          ifindex::size(32)-little,
          response_frame_id::size(32)-little,
          request_frame_id::size(32)-little,
          0::size(64)
        >>
        {:ok, address}
      {:error, error} -> {:error, error}
    end
  end
end
