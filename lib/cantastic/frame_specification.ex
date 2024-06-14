defmodule Cantastic.FrameSpecification do
  alias Cantastic.SignalSpecification
  @behaviour Access

  defdelegate fetch(term, key), to: Map
  defdelegate get(term, key, default), to: Map
  defdelegate get_and_update(term, key, fun), to: Map
  defdelegate pop(term, key), to: Map

  @authorized_yaml_keys [:id, :name, :signals, :frequency, :allowed_frequency_leeway, :allowed_missing_frames]

  defstruct [
    :id,
    :name,
    :network_name,
    :frequency,
    :frame_handlers,
    :allowed_frequency_leeway,
    :allowed_missing_frames,
    :signal_specifications
  ]

  def from_yaml(network_name, yaml_frame_specification, direction) do
    validate_keys!(network_name, yaml_frame_specification)
    yaml_signal_specifications   = yaml_frame_specification[:signals] || []
    {:ok, signal_specifications} = signal_specifications(network_name,yaml_frame_specification.id, yaml_frame_specification.name, yaml_signal_specifications)
    validate_signal_specifications!(yaml_frame_specification.name, signal_specifications, direction)
    frame_specification          = %Cantastic.FrameSpecification{
      id: yaml_frame_specification.id,
      name: yaml_frame_specification.name,
      network_name: network_name,
      frequency: yaml_frame_specification[:frequency],
      allowed_frequency_leeway: yaml_frame_specification[:allowed_frequency_leeway] || 10,
      allowed_missing_frames: yaml_frame_specification[:allowed_missing_frames] || 5,
      signal_specifications: signal_specifications,
      frame_handlers: []
    }
    validate_specification!(frame_specification, direction)
    {:ok, frame_specification}
  end

  defp validate_keys!(network_name, yaml_frame_specification) do
    defined_keys = Map.keys(yaml_frame_specification)
    invalid_keys = MapSet.difference(MapSet.new(defined_keys), MapSet.new(@authorized_yaml_keys)) |> MapSet.to_list()
    if invalid_keys != [] do
      throw "[Yaml configuration error] Frame '#{network_name}.#{yaml_frame_specification.name}' is defining invalid key: #{invalid_keys |> Enum.join(", ")}"

    end
  end

  def validate_specification!(frame_specificaton, direction) do
    if is_nil(frame_specificaton.name) do
      throw "[Yaml configuration error] Frame '#{frame_specificaton.network_name}.#{frame_specificaton.id}' is missing a 'name'."
    end
    if is_nil(frame_specificaton.id) do
      throw "[Yaml configuration error] Frame '#{frame_specificaton.network_name}.#{frame_specificaton.name}' is missing an 'id'."
    end
    if is_nil(frame_specificaton.frequency) && direction == :emit do
      throw "[Yaml configuration error] Frame '#{frame_specificaton.network_name}.#{frame_specificaton.name}' is missing a 'frequency'."
    end
  end

  defp signal_specifications(network_name, frame_id, frame_name, yaml_signal_specifications) do
    computed = yaml_signal_specifications
    |> Enum.map(fn (yaml_signal_specification) ->
      {:ok, signal_specifications} = SignalSpecification.from_yaml(network_name, frame_id, frame_name, yaml_signal_specification)
      signal_specifications
    end)
    {:ok, computed}
  end

  defp validate_signal_specifications!(frame_name, signal_specifications, direction) do
    total_length = signal_specifications
    |> Enum.reduce(0, fn (signal_specification, index) ->
      SignalSpecification.validate_specification!(signal_specification)
      if direction == :emit && signal_specification.value_start != index do
        throw "[Yaml configuration error] Emitted frame '#{frame_name}' should define all data bits, signal '#{signal_specification.name}' is not in the right order or not contiguous with the previous signal"
      else
        index + signal_specification.value_length
      end
    end)
    if total_length > 64 do
      throw "[Yaml configuration error] Emitted frame '#{frame_name}' is too long. Max frame data size is 64 bits."
    end
    if direction == :emit && rem(total_length, 8) != 0  do
      throw "[Yaml configuration error] Emitted frame '#{frame_name}' is invalid. Data must fill the used bytes entirely. Please use a static filler if needed."
    end
  end
end
