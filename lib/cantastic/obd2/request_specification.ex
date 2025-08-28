defmodule Cantastic.OBD2.RequestSpecification do
  alias Cantastic.OBD2.ParameterSpecification

  @behaviour Access

  defdelegate fetch(term, key), to: Map
  defdelegate get(term, key, default), to: Map
  defdelegate get_and_update(term, key, fun), to: Map
  defdelegate pop(term, key), to: Map

  @authorized_yaml_keys [:name, :request_frame_id, :response_frame_id, :frequency, :mode, :parameters, :anchors]

  defstruct [
    :name,
    :request_frame_id,
    :response_frame_id,
    :frequency,
    :mode,
    :parameter_specifications,
    :can_interface
  ]

  def from_yaml(network_name, can_interface, yaml_obd2_request_specification) do
    validate_keys!(network_name, yaml_obd2_request_specification)
    yaml_parameter_specifications   = yaml_obd2_request_specification[:parameters] || []
    {:ok, parameter_specifications} = parameter_specifications(network_name, yaml_obd2_request_specification.name, yaml_parameter_specifications)
    validate_parameter_specifications!(parameter_specifications)
    request_specification           = %__MODULE__{
      name: yaml_obd2_request_specification.name,
      request_frame_id: yaml_obd2_request_specification.request_frame_id,
      response_frame_id: yaml_obd2_request_specification.response_frame_id,
      frequency: yaml_obd2_request_specification.frequency,
      mode: yaml_obd2_request_specification.mode,
      parameter_specifications: parameter_specifications,
      can_interface: can_interface
    }
    validate_specification!(request_specification)
    {:ok, request_specification}
  end

  defp validate_keys!(network_name, yaml_obd2_request_specification) do
    defined_keys = Map.keys(yaml_obd2_request_specification)
    invalid_keys = MapSet.difference(MapSet.new(defined_keys), MapSet.new(@authorized_yaml_keys)) |> MapSet.to_list()
    if invalid_keys != [] do
      throw "[Yaml configuration error] OBD2 Request '#{network_name}.#{yaml_obd2_request_specification.name}' is defining invalid key: #{invalid_keys |> Enum.join(", ")}"
    end
  end

  def validate_specification!(request_specificaton) do
    if is_nil(request_specificaton.name) do
      throw "[Yaml configuration error] OBD2 Request '#{request_specificaton.network_name}.#{request_specificaton.request_frame_id}' is missing a 'name'."
    end
    if is_nil(request_specificaton.request_frame_id) do
      throw "[Yaml configuration error] OBD2 Request '#{request_specificaton.network_name}.#{request_specificaton.name}' is missing an 'request_frame_id'."
    end
    if is_nil(request_specificaton.response_frame_id) do
      throw "[Yaml configuration error] OBD2 Request '#{request_specificaton.network_name}.#{request_specificaton.name}' is missing an 'response_frame_id'."
    end
  end

  defp parameter_specifications(network_name, request_name, yaml_parameter_specifications) do
    computed = yaml_parameter_specifications
    |> Enum.map(fn (yaml_parameter_specification) ->
      {:ok, parameter_specification} = ParameterSpecification.from_yaml(network_name, request_name, yaml_parameter_specification)
      parameter_specification
    end)
    {:ok, computed}
  end


  defp validate_parameter_specifications!(parameter_specifications) do
    parameter_specifications |> Enum.each(fn(parameter_specification) ->
      ParameterSpecification.validate_specification!(parameter_specification)
    end)
  end
end
