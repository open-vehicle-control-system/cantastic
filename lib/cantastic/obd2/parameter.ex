defmodule Cantastic.Parameter do
  alias Decimal, as: D

  defstruct [
    :name,
    :request_name,
    :kind,
    :value,
    :raw_value,
    :unit
  ]

  def to_string(parameter) do
    "[OBD2 Parameter] #{parameter.request_name}.#{parameter.name} = #{parameter.value}"
  end

  def interpret(frame, parameter_specification) do
    parameter = %__MODULE__{
      name: parameter_specification.name,
      request_name: parameter_specification.request_name,
      kind: parameter_specification.kind,
      unit: parameter_specification.unit
    }

    {:ok, raw_value, value_length} = extract_raw_value(frame.raw_data, parameter_specification)

    try do
      decimal = interpret_decimal(raw_value, parameter_specification, value_length) |> D.round(parameter_specification.precision)
      value   = case parameter_specification.kind do
        "decimal" ->
          decimal
        "integer" ->
          decimal |> D.to_integer()
      end
      {:ok, %{parameter | value: value, raw_value: raw_value}}
    rescue
      error in MatchError ->
        {:error, error}
    end
  end

  defp interpret_decimal(raw_val, parameter_specification, value_length) do
    int = case {parameter_specification.endianness, parameter_specification.sign} do
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
    D.new(int) |> D.mult(parameter_specification.scale) |> D.add(parameter_specification.offset)
  end

  defp extract_raw_value(raw_data, parameter_specification) do
    case parameter_specification.value_start do
      value_start when is_integer(value_start) ->
        raw_value = extract_segment(raw_data, value_start, parameter_specification.value_length)
        {:ok, raw_value, parameter_specification.value_length}
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
