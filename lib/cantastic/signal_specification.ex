defmodule Cantastic.SignalSpecification do
  alias Cantastic.Util
  alias Decimal, as: D

  @valid_kinds ["decimal", "integer", "static", "enum"]
  @valid_signs ["signed", "unsigned"]
  @valid_endiannesses ["big", "little"]
  @authorized_yaml_keys [:name, :kind, :precision, :sign, :value_start, :value_length, :endianness, :mapping, :unit, :scale, :offset, :value]

  defstruct [
    :name,
    :kind,
    :precision,
    :network_name,
    :frame_id,
    :frame_name,
    :value_start,
    :value_length,
    :endianness,
    :mapping,
    :reverse_mapping,
    :unit,
    :scale,
    :offset,
    :sign,
    :value
  ]

  def from_yaml(network_name, frame_id, frame_name, yaml_signal_specification) do
    validate_keys!(network_name, frame_name, yaml_signal_specification)

    value_length         = yaml_signal_specification.value_length
    signal_specification = %Cantastic.SignalSpecification{
      name: yaml_signal_specification.name,
      network_name: network_name,
      frame_id: frame_id,
      frame_name: frame_name,
      kind: yaml_signal_specification[:kind] || "decimal",
      precision: yaml_signal_specification[:precision] || 2,
      sign: yaml_signal_specification[:sign] || "unsigned",
      value_start: yaml_signal_specification.value_start,
      value_length: value_length,
      endianness: yaml_signal_specification[:endianness] || "little",
      mapping: compute_mapping(yaml_signal_specification[:mapping], value_length),
      reverse_mapping: compute_reverse_mapping(yaml_signal_specification[:mapping], value_length),
      unit: yaml_signal_specification[:unit],
      scale: D.new(yaml_signal_specification[:scale] || "1"),
      offset: D.new(yaml_signal_specification[:offset] || "0"),
      value: yaml_signal_specification[:value] |> Util.integer_to_bin_big(value_length)
    }
    {:ok, signal_specification}
  end

  defp validate_keys!(network_name, frame_name, yaml_signal_specification) do
    defined_keys = Map.keys(yaml_signal_specification)
    invalid_keys = MapSet.difference(MapSet.new(defined_keys), MapSet.new(@authorized_yaml_keys)) |> MapSet.to_list()
    if invalid_keys != [] do
      throw "[Yaml configuration error] Signal '#{network_name}.#{frame_name}.#{yaml_signal_specification.name}' is defining invalid keys: #{invalid_keys |> Enum.join(", ")}"
    end
  end

  def validate_specification!(signal_specification) do
    if is_nil(signal_specification.name) do
      throw "[Yaml configuration error] Signal '#{signal_specification.network_name}.#{signal_specification.frame_name}.#{signal_specification.name}' is missing a 'name'."
    end
    if is_nil(signal_specification.value_start) do
      throw "[Yaml configuration error] Signal '#{signal_specification.network_name}#{signal_specification.frame_name}.#{signal_specification.name}' is missing a 'value_start'."
    end
    if is_nil(signal_specification.value_length) do
      throw "[Yaml configuration error] Signal '#{signal_specification.network_name}#{signal_specification.frame_name}.#{signal_specification.name}' is missing a 'value_length'."
    end
    if !Enum.member?(@valid_kinds, signal_specification.kind) do
      throw "[Yaml configuration error] Signal '#{signal_specification.network_name}#{signal_specification.frame_name}.#{signal_specification.name}' is using an invalid kind: '#{signal_specification.kind}'"
    end
    if !Enum.member?(@valid_signs, signal_specification.sign) do
      throw "[Yaml configuration error] Signal '#{signal_specification.network_name}#{signal_specification.frame_name}.#{signal_specification.name}' is using an invalid sign: '#{signal_specification.sign}'"
    end
    if !Enum.member?(@valid_endiannesses, signal_specification.endianness) do
      throw "[Yaml configuration error] Signal '#{signal_specification.network_name}#{signal_specification.frame_name}.#{signal_specification.name}' is using an invalid endianness: '#{signal_specification.endianness}'"
    end

    case signal_specification.kind do
      "enum" ->
        if !is_map(signal_specification.mapping) || signal_specification.mapping == %{} do
          throw "[Yaml configuration error] A mapping is missing for the signal '#{signal_specification.network_name}#{signal_specification.frame_name}.#{signal_specification.name}' of kind 'enum'."
        end
      "static" ->
        if is_nil(signal_specification.value) do
          throw "[Yaml configuration error] A value is missing for the signal '#{signal_specification.network_name}#{signal_specification.frame_name}.#{signal_specification.name}' of kind 'static'."
        end
      _ -> :ok
    end
  end

  defp compute_mapping(nil, _value_length), do: nil
  defp compute_mapping(mapping, value_length) do
    mapping |> Map.keys() |> Enum.reduce(%{}, fn(atom_key, computed_mapping) ->
      key = atom_key |> Atom.to_string() |> Util.string_to_integer() |>  Util.integer_to_bin_big(value_length)
      computed_mapping |> Map.put(key, mapping[atom_key])
    end)
  end

  defp compute_reverse_mapping(nil, _value_length), do: nil
  defp compute_reverse_mapping(mapping, value_length) do
    mapping |> Map.keys() |> Enum.reduce(%{}, fn(atom_value, computed_mapping) ->
      string_value = atom_value |> Atom.to_string()
      value        = string_value |> Util.string_to_integer() |> Util.integer_to_bin_big(value_length)
      computed_mapping |> Map.put(mapping[atom_value], value)
    end)
  end
end
