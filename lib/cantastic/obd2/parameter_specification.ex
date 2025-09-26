defmodule Cantastic.OBD2.ParameterSpecification do
  @moduledoc false

  alias Decimal, as: D

  @valid_kinds ["decimal", "integer"]
  @valid_signs ["signed", "unsigned"]
  @valid_endiannesses ["big", "little"]
  @authorized_yaml_keys [:name, :id, :kind, :precision, :sign, :value_length, :endianness, :unit, :scale, :offset]

  defstruct [
    :name,
    :id,
    :kind,
    :precision,
    :network_name,
    :request_name,
    :value_length,
    :endianness,
    :unit,
    :scale,
    :offset,
    :sign,
  ]

  def from_yaml(network_name, request_name, yaml_parameter_specification) do
    validate_keys!(network_name, request_name, yaml_parameter_specification)

    parameter_specification = %__MODULE__{
      name: yaml_parameter_specification.name,
      id: yaml_parameter_specification.id,
      network_name: network_name,
      request_name: request_name,
      kind: yaml_parameter_specification[:kind] || "decimal",
      precision: yaml_parameter_specification[:precision] || 2,
      sign: yaml_parameter_specification[:sign] || "unsigned",
      value_length: yaml_parameter_specification.value_length,
      endianness: yaml_parameter_specification[:endianness] || "big",
      unit: yaml_parameter_specification[:unit],
      scale: D.new(yaml_parameter_specification[:scale] || "1"),
      offset: D.new(yaml_parameter_specification[:offset] || "0"),
    }
    {:ok, parameter_specification}
  end

  defp validate_keys!(network_name, request_name, yaml_parameter_specification) do
    defined_keys = Map.keys(yaml_parameter_specification)
    invalid_keys = MapSet.difference(MapSet.new(defined_keys), MapSet.new(@authorized_yaml_keys)) |> MapSet.to_list()
    if invalid_keys != [] do
      throw "[Yaml configuration error] Parameter '#{network_name}.#{request_name}.#{yaml_parameter_specification.name}' is defining invalid keys: #{invalid_keys |> Enum.join(", ")}"
    end
  end

  def validate_specification!(parameter_specification) do
    if is_nil(parameter_specification.name) do
      throw "[Yaml configuration error] OBD2 Parameter '#{parameter_specification.network_name}.#{parameter_specification.request_name}.#{parameter_specification.name}' is missing a 'name'."
    end
    if is_nil(parameter_specification.id) do
      throw "[Yaml configuration error] OBD2 Parameter '#{parameter_specification.network_name}.#{parameter_specification.request_name}.#{parameter_specification.name}' is missing an 'id'."
    end
    if is_nil(parameter_specification.value_length) do
      throw "[Yaml configuration error] OBD2 Parameter '#{parameter_specification.network_name}#{parameter_specification.request_name}.#{parameter_specification.name}' is missing a 'value_length'."
    end
    if !Enum.member?(@valid_kinds, parameter_specification.kind) do
      throw "[Yaml configuration error] OBD2 Parameter '#{parameter_specification.network_name}#{parameter_specification.request_name}.#{parameter_specification.name}' is using an invalid kind: '#{parameter_specification.kind}'"
    end
    if !Enum.member?(@valid_signs, parameter_specification.sign) do
      throw "[Yaml configuration error] OBD2 Parameter '#{parameter_specification.network_name}#{parameter_specification.request_name}.#{parameter_specification.name}' is using an invalid sign: '#{parameter_specification.sign}'"
    end
    if !Enum.member?(@valid_endiannesses, parameter_specification.endianness) do
      throw "[Yaml configuration error] OBD2 Parameter '#{parameter_specification.network_name}#{parameter_specification.request_name}.#{parameter_specification.name}' is using an invalid endianness: '#{parameter_specification.endianness}'"
    end
  end
end
