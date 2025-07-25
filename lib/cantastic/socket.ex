defmodule Cantastic.Socket do
  require Logger

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
  @flags @can_isotp_tx_padding

  # Source: https://docs.kernel.org/networking/iso15765-2.html#iso-tp-socket-options
  @can_isotp_options <<@flags::size(32)-little, 0::size(32)-little, 0::size(8)-little, 0::size(8)-little, 0::size(8)-little, 0::size(8)-little>>


  @sending_timeout 100

  @stamp_flags 0x8906 # SIOCGSTAMP: 0x8906 - SIOCGSTAMPNS: 0x8907 - SIOCSHWTSTAMP": 0x89b0 - SIOCGHWTSTAMP: 0x89b1

  def bind_raw(interface) do
    bind(interface, :raw, 0, 0)
  end

  def bind_isotp(interface, request_frame_id, response_frame_id) do
    bind(interface, :isotp, request_frame_id, response_frame_id)
  end

  defp bind(interface, protocol, request_frame_id, response_frame_id) do
    charlist_interface = interface |> String.to_charlist()
    with {:ok, socket}  <- :socket.open(@protocol_family, @protocol_types[protocol], @protocols[protocol]),
         {:ok, ifindex} <- :socket.ioctl(socket, :gifindex, charlist_interface),
         {:ok, address} <- build_raw_address(ifindex, request_frame_id, response_frame_id),
         :ok            <- :socket.setopt_native(socket, {:socket, @protocol_family}, @stamp_flags),
         :ok            <- :socket.setopt_native(socket, {@sol_can_isotp, @can_isotp_opts}, @can_isotp_options), # TODO: apply only to isotp OBD sockets
         :ok            <- :socket.bind(socket, %{:family => @protocol_family, :addr => address})
    do
      {:ok, socket}
    else
      {:error, :enodev} -> {:error, "CAN interface not found by libsocketcan. Make sure it is configured and enabled first with '$ ip link show'"}
      {:error, error} -> {:error, error}
    end
  end

  defp build_raw_address(ifindex, request_frame_id, response_frame_id) do
    # Source: https://elixirforum.com/t/erlang-socket-module-for-socketcan-on-nerves-device/57294/6
    address = <<
      0::size(16)-little,
      ifindex::size(32)-little,
      response_frame_id::size(32)-little,
      request_frame_id::size(32)-little,
      0::size(64)
    >>
    {:ok, address}
  end

  def send(socket, raw) do
    case :socket.send(socket, raw, @sending_timeout) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

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

    reception_timestamp = timestamp_seconds * 1_000_000 + timestamp_usec
    {:ok, raw}
  end
end
