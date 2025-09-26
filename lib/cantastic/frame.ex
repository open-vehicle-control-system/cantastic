defmodule Cantastic.Frame do
  @moduledoc """
    `Cantastic.Frame` is a `Struct` used to represent one CAN frame.

    You will receive this `Struct` fom `Cantastic.Receiver` each time a frame is received on the CAN network.

    The attributes are the following:

    * `:id` The frame id (`Integer`).
    * `:name` The frame name.
    * `:byte_number` The number of data bytes in this frame.
    * `:raw_data` The raw bytes received on the CAN network.
    * `:network_name` The name of the CAN network as defined in your YAML file.
    * `:created_at` The `DateTime` at which the   `Struct` has been created in OTP.
    * `:reception_timestamp`  The `DateTime` at which the frame was received by the kernel.
    * `:signals` A `Map` of the signals contained in this frame.
  """

  alias Cantastic.{Util, Signal, FrameSpecification}
  alias Decimal, as: D

  defstruct [
    :id,
    :name,
    :byte_number,
    :raw_data,
    :network_name,
    :created_at,
    :reception_timestamp,
    signals: %{}
  ]

  @doc false
  def build_raw(frame_specification, parameters) do
    {:ok, raw_data} = build_raw_data(frame_specification, parameters)
    frame = %__MODULE__{
      id: frame_specification.id,
      network_name: frame_specification.network_name,
      raw_data: raw_data,
      byte_number: frame_specification.byte_number,
      created_at: DateTime.utc_now()
    }
    {:ok, to_raw(frame)}
  end

  @doc false
  defp build_raw_data(frame_specification, parameters) do
    raw_data = frame_specification.signal_specifications
    |> Enum.reduce(<<>>, fn (signal_specification, raw_data) ->
      value      = (parameters || %{})[signal_specification.name]
      raw_signal = Signal.build_raw(signal_specification, value)
      if is_nil(raw_signal), do: throw "Signal '#{frame_specification.network_name}.#{frame_specification.name}.#{signal_specification.name}' value is missing from emitter data."
      <<raw_data::bitstring, raw_signal::bitstring>>
    end)
    |> include_checksum_if_required(frame_specification, parameters)
    {:ok, raw_data}
  end

  @doc false
  defp include_checksum_if_required(raw_data, %FrameSpecification{checksum_required: false}, _), do: raw_data
  defp include_checksum_if_required(raw_data, frame_specification, parameters) do
    checksum               = parameters[frame_specification.checksum_signal_specification.name].(raw_data)
    checksum_specification = frame_specification.checksum_signal_specification
    raw_checksum           = Signal.build_raw_decimal(checksum_specification, D.new(checksum))
    head_length            = checksum_specification.value_start
    <<head::bitstring-size(head_length), tail::bitstring>> = raw_data
    <<head::bitstring, raw_checksum::bitstring, tail::bitstring>>
  end

  @doc false
  def interpret(frame, frame_specification) do
    signals = frame_specification.signal_specifications |> Enum.reduce(%{}, fn(signal_specification, acc) ->
      {:ok, signal} =  Signal.interpret(frame, signal_specification)
      put_in(acc, [signal.name], signal)
    end)
    frame = %{frame | name: frame_specification.name, signals: signals}
    {:ok, frame}
  end

  @doc """
  Returns a `String` representation of the frame, used for debugging.

  ## Example

      iex> Cantastic.Frame.to_string(frame)
      "[Frame] my_network - 0x7A1 3 00 AA BB"

  """
  def to_string(frame) do
    "[Frame] #{frame.network_name} - #{format_id(frame)}  [#{frame.byte_number}]  #{format_data(frame)}"
  end

  @doc false
  def format_id(frame) do
    frame.id |> Util.integer_to_hex()
  end

  @doc false
  def format_data(frame) do
    frame.raw_data
    |> Util.bin_to_hex()
    |> String.split("", trim: true)
    |> Enum.chunk_every(2)
    |> Enum.join(" ")
  end

  @doc false
  def to_raw(frame) do
    byte_number = frame.byte_number
    padding     = 8 - byte_number
    << frame.id::little-integer-size(16),
      0::2 * 8,
      byte_number,
      0::3 * 8
    >> <>
    frame.raw_data <>
    <<0::padding * 8>>
  end
end
