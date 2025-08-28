defmodule Cantastic.OBD2.Parameter do
  alias Decimal, as: D

  defdelegate fetch(term, key), to: Map
  defdelegate get(term, key, default), to: Map
  defdelegate get_and_update(term, key, fun), to: Map
  defdelegate pop(term, key), to: Map

  defstruct [
    :name,
    :id,
    :request_name,
    :kind,
    :value,
    :raw_value,
    :unit
  ]

  def to_string(parameter) do
    "[OBD2 Parameter] #{parameter.request_name}.#{parameter.name} = #{parameter.value}"
  end

  def interpret(raw_parameters, parameter_specification) do
    parameter = %__MODULE__{
      name: parameter_specification.name,
      id: parameter_specification.id,
      request_name: parameter_specification.request_name,
      kind: parameter_specification.kind,
      unit: parameter_specification.unit
    }
    try do
      value_length = parameter_specification.value_length
      id           = parameter.id
      <<^id::integer-size(8), raw_value::bitstring-size(value_length), truncated_raw_parameters::bitstring>> = raw_parameters
      decimal = interpret_decimal(raw_value, parameter_specification, value_length) |> D.round(parameter_specification.precision)
      value   = case parameter_specification.kind do
        "decimal" ->
          decimal
        "integer" ->
          decimal |> D.to_integer()
      end
      {:ok, %{parameter | value: value, raw_value: raw_value}, truncated_raw_parameters}
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
end
