defmodule Cantastic.Signal do
  alias Decimal, as: D

  defstruct [
    :name,
    :frame_name,
    :value,
    :unit,
    :kind
  ]

  def to_string(signal) do
    "[Signal] #{signal.frame_name}.#{signal.name} = #{signal.value}"
  end

  def build_raw(signal_specification, value) do
    case signal_specification.kind do
      "static" ->
        signal_specification.value
      "integer" ->
        build_raw_decimal(signal_specification, D.new(value))
      "decimal" ->
        build_raw_decimal(signal_specification, value)
      "enum" ->
        signal_specification.reverse_mapping[value]
      "checksum" ->
        <<>>
    end
  end

  def build_raw_decimal(signal_specification, value) do
    offsetted = value |> D.sub(signal_specification.offset)
    scaled    = offsetted |> D.div(signal_specification.scale)
    int       = scaled |> D.round() |> D.to_integer()
    case signal_specification.endianness do
      "little" ->
        <<int::little-integer-size(signal_specification.value_length)>>
      "big"    ->
        <<int::big-integer-size(signal_specification.value_length)>>
    end
  end

  def interpret(frame, signal_specification) do
    signal = %__MODULE__{
      name: signal_specification.name,
      frame_name: signal_specification.frame_name,
      kind: signal_specification.kind,
      unit: signal_specification.unit,
      value: nil
    }

    {:ok, raw_value, value_length} = extract_raw_value(frame.raw_data, signal_specification)

    try do
      value = case signal_specification.kind do
        "static" ->
          raw_value
        "decimal" ->
          interpret_decimal(raw_value, signal_specification, value_length)
          |> D.round(signal_specification.precision)
        "integer" ->
          interpret_decimal(raw_value, signal_specification, value_length)
          |> D.round()
          |> D.to_integer()
        "enum" ->
          signal_specification.mapping[raw_value]
      end
      {:ok, %{signal | value: value}}
    rescue
      error in MatchError ->
        {:error, error}
    end
  end

  defp interpret_decimal(raw_val, signal_specification, value_length) do
    int = case {signal_specification.endianness, signal_specification.sign} do
      {"little", "signed"} ->
        <<val::little-signed-integer-size(value_length)>> = raw_val
        val
      {"little", "unsigned"} ->
        <<val::little-unsigned-integer-size(value_length)>> = raw_val
        val
      {"big", "signed"} ->
        <<val::big-signed-integer-size(value_length)>> = raw_val
        val
      {"big", "unsigned"} ->
        <<val::big-unsigned-integer-size(value_length)>> = raw_val
        val
    end
    D.new(int) |> D.mult(signal_specification.scale) |> D.add(signal_specification.offset)
  end

  defp extract_raw_value(raw_data, signal_specification) do
    case signal_specification.value_start do
      value_start when is_integer(value_start) ->
        raw_value = extract_segment(raw_data, value_start, signal_specification.value_length)
        {:ok, raw_value, signal_specification.value_length}
      ranges ->
        {raw_value, value_length} = ranges
          |> Enum.reduce({<<>>, 0}, fn(range, {value_accumulator, value_length_accumulator}) ->
            partial_raw_value = extract_segment(raw_data, range.start, range.length)
            {<<partial_raw_value::bitstring, value_accumulator::bitstring>>, value_length_accumulator + range.length}
          end)
          {:ok, raw_value, value_length}
    end
  end

  defp extract_segment(raw_data, head_length, value_length) do
    <<_head::bitstring-size(head_length), segment::bitstring-size(value_length), _tail::bitstring>> = raw_data
    segment
  end
end
