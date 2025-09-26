defmodule Cantastic.OBD2.Parameter do
  @moduledoc """
    `Cantastic.OBD2.Parameter` is a `Struct` used to represent one CAN OBD2 parameter.

    Each received `Cantastic.OBD2.Response` contains a list of `:parameters`

    The attributes are the following:

    * `:name` The paramter's name, as defined in your YAML file.
    * `:id` The paramter's, as defined in your YAML file.
    * `:request_name` The OBD2 request's name, as defined in your YAML file.
    * `:raw_value` The raw value received on the CAN network.
    * `:unit` The unit defined in your YAML file (`String`).
    * `:kind` The kind defined in your YAML file, one off:
      * `:decimal`
      * `:integer`
  """

  alias Decimal, as: D

  @doc false
  defdelegate fetch(term, key), to: Map
  @doc false
  defdelegate get(term, key, default), to: Map
  @doc false
  defdelegate get_and_update(term, key, fun), to: Map
  @doc false
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

  @doc """
  Returns a `String` representation of the parameter, used for debugging.

  ## Example

      iex> Cantastic.OBD2.Parameter.to_string(parameter)
      "[OBD2 Parameter] my_request_name.parameter_name = 12"

  """
  def to_string(parameter) do
    "[OBD2 Parameter] #{parameter.request_name}.#{parameter.name} = #{parameter.value}"
  end

  @doc false
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

  @doc false
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
