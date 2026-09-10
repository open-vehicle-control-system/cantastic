defmodule Cantastic.FrameSpecification do
  @moduledoc false

  alias Cantastic.SignalSpecification
  @behaviour Access

  defdelegate fetch(term, key), to: Map
  defdelegate get(term, key, default), to: Map
  defdelegate get_and_update(term, key, fun), to: Map
  defdelegate pop(term, key), to: Map

  # SocketCAN's can_id is 32 bits: the identifier in the low 29 bits and
  # CAN_EFF_FLAG on top when the frame uses the 29-bit (extended) format.
  # A standard and an extended frame may carry the same numeric id on one
  # bus and be two different frames, so specifications are keyed by the
  # full can_id, not by the bare id.
  @eff_flag 0x80000000
  @max_standard_id 0x7FF
  @max_extended_id 0x1FFFFFFF

  @authorized_yaml_keys [
    :id,
    :extended,
    :name,
    :signals,
    :frequency,
    :allowed_frequency_leeway,
    :allowed_missing_frames,
    :required_on_time_frames,
    :anchors
  ]

  defstruct [
    :id,
    :name,
    :network_name,
    :frequency,
    :frame_handlers,
    :allowed_frequency_leeway,
    :allowed_missing_frames,
    :allowed_missing_frames_period,
    :required_on_time_frames,
    :signal_specifications,
    :data_length,
    :byte_number,
    :checksum_signal_specification,
    extended: false,
    checksum_required: false
  ]

  def from_yaml(network_name, yaml_frame_specification, direction) do
    validate_keys!(network_name, yaml_frame_specification)
    frame_name = yaml_frame_specification.name
    yaml_signal_specifications = yaml_frame_specification[:signals] || []

    {:ok, signal_specifications} =
      signal_specifications(
        network_name,
        yaml_frame_specification.id,
        yaml_frame_specification.name,
        yaml_signal_specifications
      )

    data_length =
      compute_data_length_and_validate_signal_specifications!(
        network_name,
        frame_name,
        signal_specifications,
        direction
      )

    checksum_signal_specification =
      find_and_validate_checksum_signal!(network_name, frame_name, signal_specifications)

    frame_specification = %Cantastic.FrameSpecification{
      id: yaml_frame_specification.id,
      extended: yaml_frame_specification[:extended] == true,
      name: yaml_frame_specification.name,
      network_name: network_name,
      frequency: yaml_frame_specification[:frequency],
      allowed_frequency_leeway: yaml_frame_specification[:allowed_frequency_leeway] || 10,
      allowed_missing_frames: yaml_frame_specification[:allowed_missing_frames] || 5,
      allowed_missing_frames_period:
        yaml_frame_specification[:allowed_missing_frames_period] || 5_000,
      required_on_time_frames: yaml_frame_specification[:required_on_time_frames] || 5,
      signal_specifications: signal_specifications,
      frame_handlers: [],
      data_length: data_length,
      byte_number: Integer.floor_div(data_length, 8),
      checksum_required: !is_nil(checksum_signal_specification),
      checksum_signal_specification: checksum_signal_specification
    }

    validate_specification!(frame_specification, direction)
    {:ok, frame_specification}
  end

  defp validate_keys!(network_name, yaml_frame_specification) do
    defined_keys = Map.keys(yaml_frame_specification)

    invalid_keys =
      MapSet.difference(MapSet.new(defined_keys), MapSet.new(@authorized_yaml_keys))
      |> MapSet.to_list()

    if invalid_keys != [] do
      throw(
        "[Yaml configuration error] Frame '#{network_name}.#{yaml_frame_specification.name}' is defining invalid key: #{invalid_keys |> Enum.join(", ")}"
      )
    end
  end

  def validate_specification!(frame_specificaton, direction) do
    if is_nil(frame_specificaton.name) do
      throw(
        "[Yaml configuration error] Frame '#{frame_specificaton.network_name}.#{frame_specificaton.id}' is missing a 'name'."
      )
    end

    if is_nil(frame_specificaton.id) do
      throw(
        "[Yaml configuration error] Frame '#{frame_specificaton.network_name}.#{frame_specificaton.name}' is missing an 'id'."
      )
    end

    validate_id_range!(frame_specificaton)

    if is_nil(frame_specificaton.frequency) && direction == :emit do
      throw(
        "[Yaml configuration error] Frame '#{frame_specificaton.network_name}.#{frame_specificaton.name}' is missing a 'frequency'."
      )
    end
  end

  defp validate_id_range!(%{extended: true} = spec) when spec.id > @max_extended_id do
    throw(
      "[Yaml configuration error] Frame '#{spec.network_name}.#{spec.name}' has id 0x#{Integer.to_string(spec.id, 16)}, above the 29-bit maximum 0x1FFFFFFF."
    )
  end

  defp validate_id_range!(%{extended: false} = spec) when spec.id > @max_standard_id do
    throw(
      "[Yaml configuration error] Frame '#{spec.network_name}.#{spec.name}' has id 0x#{Integer.to_string(spec.id, 16)}, above the 11-bit maximum 0x7FF. Add 'extended: true' if it is a 29-bit frame."
    )
  end

  defp validate_id_range!(_spec), do: :ok

  @doc """
  The SocketCAN `can_id` of a frame: its id, with `CAN_EFF_FLAG` set when
  the frame is extended. This is what tells a standard frame from an
  extended one carrying the same numeric id, so it is the key under which
  specifications are stored and looked up.
  """
  def can_id(%{id: id, extended: true}), do: Bitwise.bor(id, @eff_flag)
  def can_id(%{id: id}), do: id

  @doc false
  def can_id(id, true), do: Bitwise.bor(id, @eff_flag)
  def can_id(id, _extended), do: id

  @doc false
  def eff_flag, do: @eff_flag

  defp signal_specifications(network_name, frame_id, frame_name, yaml_signal_specifications) do
    computed =
      yaml_signal_specifications
      |> Enum.map(fn yaml_signal_specification ->
        {:ok, signal_specifications} =
          SignalSpecification.from_yaml(
            network_name,
            frame_id,
            frame_name,
            yaml_signal_specification
          )

        signal_specifications
      end)

    {:ok, computed}
  end

  defp find_and_validate_checksum_signal!(network_name, frame_name, signal_specifications) do
    checksum_specifications =
      signal_specifications |> Enum.filter(fn i -> i.kind == "checksum" end)

    case checksum_specifications do
      nil ->
        nil

      _ ->
        if length(checksum_specifications) > 1 do
          throw(
            "[Yaml configuration error] Frame '#{network_name}.#{frame_name}' is defining more than one checksum signal while at most one is allowed."
          )
        end

        checksum_specifications |> List.first()
    end
  end

  defp compute_data_length_and_validate_signal_specifications!(
         network_name,
         frame_name,
         signal_specifications,
         direction
       ) do
    total_length =
      signal_specifications
      |> Enum.reduce(0, fn signal_specification, index ->
        SignalSpecification.validate_specification!(signal_specification)

        if direction == :emit && signal_specification.value_start != index do
          throw(
            "[Yaml configuration error] Emitted frame '#{network_name}.#{frame_name}' should define all data bits, signal '#{signal_specification.name}' is not in the right order or not contiguous with the previous signal"
          )
        else
          index + signal_specification.value_length
        end
      end)

    if total_length > 64 do
      throw(
        "[Yaml configuration error] Frame '#{network_name}.#{frame_name}' is too long. Max frame data size is 64 bits."
      )
    end

    if direction == :emit && rem(total_length, 8) != 0 do
      throw(
        "[Yaml configuration error] Emitted frame '#{network_name}.#{frame_name}' is invalid. Data must fill the used bytes entirely. Please use a static filler if needed."
      )
    end

    total_length
  end
end
