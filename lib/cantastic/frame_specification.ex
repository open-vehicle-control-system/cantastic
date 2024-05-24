defmodule Cantastic.FrameSpecification do
  alias Cantastic.SignalSpecification
  @behaviour Access

  defdelegate fetch(term, key), to: Map
  defdelegate get(term, key, default), to: Map
  defdelegate get_and_update(term, key, fun), to: Map
  defdelegate pop(term, key), to: Map

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
    yaml_signal_specifications   = yaml_frame_specification[:signals] || []
    {:ok, signal_specifications} = signal_specifications(yaml_frame_specification.id, yaml_frame_specification.name, yaml_signal_specifications)
    validate_frequency!(yaml_frame_specification, direction)
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
    {:ok, frame_specification}
  end

  defp signal_specifications(frame_id, frame_name, yaml_signal_specifications) do
    computed = yaml_signal_specifications
    |> Enum.map(fn (yaml_signal_specification) ->
      {:ok, signal_specifications} = SignalSpecification.from_yaml(frame_id, frame_name, yaml_signal_specification)
      signal_specifications
    end)
    {:ok, computed}
  end

  defp validate_frequency!(_yaml_frame_specification, :receive), do: nil
  defp validate_frequency!(yaml_frame_specification, :emit) do
    if !yaml_frame_specification[:frequency] do
      throw "[Yaml configuration error] Emitted frame '#{yaml_frame_specification.name}' is missing a frequency, please add it in the Yaml configuration."
    end
  end

  defp validate_signal_specifications!(_frame_name, _signal_specifications, :receive), do: nil
  defp validate_signal_specifications!(frame_name, signal_specifications, :emit) do
    total_length = signal_specifications
    |> Enum.reduce(0, fn (signal_specification, index) ->
      if signal_specification.value_start != index do
        throw "[Yaml configuration error] Emitted frame '#{frame_name}' should define all data bits, signal '#{signal_specification.name}' is not in the right order or not contiguous with the previous signal"
      else
        index + signal_specification.value_length
      end
    end)
    if total_length > 64 do
      throw "[Yaml configuration error] Emitted frame '#{frame_name}' is too long. Max frame data size is 64 bits."
    end
    if rem(total_length, 8) != 0  do
      throw "[Yaml configuration error] Emitted frame '#{frame_name}' is invalid. Data must fill the used bytes entirely. Please use a static filler if needed."
    end
  end
end
