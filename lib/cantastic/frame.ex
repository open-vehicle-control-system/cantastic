defmodule Cantastic.Frame do
  alias Cantastic.{Util, Signal, FrameSpecification}
  alias Decimal, as: D

  defstruct [
    :id,
    :name,
    :byte_number,
    :raw_data,
    :network_name,
    created_at: DateTime.utc_now(),
    signals: %{}
  ]

  def build_raw(frame_specification, parameters) do
    {:ok, raw_data} = build_raw_data(frame_specification, parameters)
    frame = %__MODULE__{
      id: frame_specification.id,
      network_name: frame_specification.network_name,
      raw_data: raw_data,
      byte_number: frame_specification.byte_number
    }
    {:ok, to_raw(frame)}
  end

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

  defp include_checksum_if_required(raw_data, %FrameSpecification{checksum_required: false}, _), do: raw_data
  defp include_checksum_if_required(raw_data, frame_specification, parameters) do
    checksum               = parameters[frame_specification.checksum_signal_specification.name].(raw_data)
    checksum_specification = frame_specification.checksum_signal_specification
    raw_checksum           = Signal.build_raw_decimal(checksum_specification, D.new(checksum))
    head_length            = checksum_specification.value_start
    <<head::bitstring-size(head_length), tail::bitstring>> = raw_data
    <<head::bitstring, raw_checksum::bitstring, tail::bitstring>>
  end

  def interpret(frame, frame_specification) do
    signals = frame_specification.signal_specifications |> Enum.reduce(%{}, fn(signal_specification, acc) ->
      {:ok, signal} =  Signal.interpret(frame, signal_specification)
      put_in(acc, [signal.name], signal)
    end)
    frame = %{frame | name: frame_specification.name, signals: signals}
    {:ok, frame}
  end

  def to_string(frame) do
    "[Frame] #{frame.network_name} - #{format_id(frame)}  [#{frame.byte_number}]  #{format_data(frame)}"
  end

  def format_id(frame) do
    frame.id |> Util.integer_to_hex()
  end

  def format_data(frame) do
    frame.raw_data
    |> Util.bin_to_hex()
    |> String.split("", trim: true)
    |> Enum.chunk_every(2)
    |> Enum.join(" ")
  end

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
