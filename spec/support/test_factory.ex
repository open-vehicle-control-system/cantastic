defmodule Cantastic.TestFactory do
  @moduledoc false
  alias Cantastic.{SignalSpecification, FrameSpecification}
  alias Cantastic.OBD2.{ParameterSpecification, RequestSpecification}
  alias Decimal, as: D

  def integer_signal_specification(overrides \\ %{}) do
    base = %SignalSpecification{
      name: Faker.Cat.name(),
      kind: "integer",
      precision: 2,
      frame_id: 1,
      frame_name: Faker.Cat.name(),
      value_start: 0,
      value_length: 8,
      endianness: "little",
      mapping: nil,
      reverse_mapping: nil,
      unit: "RPM",
      scale: D.new(1),
      offset: D.new(0),
      sign: "unsigned",
      value: Faker.random_between(0, 10000)
    }
    Map.merge(base, Map.new(overrides))
  end

  def decimal_signal_specification(overrides \\ %{}) do
    integer_signal_specification(Map.merge(%{kind: "decimal"}, Map.new(overrides)))
  end

  def static_signal_specification(value, value_length \\ 8, overrides \\ %{}) do
    integer_signal_specification(
      Map.merge(
        %{
          kind: "static",
          value: <<value::big-integer-size(value_length)>>,
          value_length: value_length
        },
        Map.new(overrides)
      )
    )
  end

  def enum_signal_specification(mapping, value_length \\ 8, overrides \\ %{}) do
    reverse = mapping |> Enum.reduce(%{}, fn({k, v}, acc) ->
      Map.put(acc, v, <<k::big-integer-size(value_length)>>)
    end)
    bin_keyed = mapping |> Enum.reduce(%{}, fn({k, v}, acc) ->
      Map.put(acc, <<k::big-integer-size(value_length)>>, v)
    end)
    integer_signal_specification(
      Map.merge(
        %{
          kind: "enum",
          value_length: value_length,
          mapping: bin_keyed,
          reverse_mapping: reverse
        },
        Map.new(overrides)
      )
    )
  end

  def frame_specification(overrides \\ %{}) do
    base = %FrameSpecification{
      id: 0x100,
      name: "test_frame",
      network_name: :test_network,
      frequency: 100,
      allowed_frequency_leeway: 10,
      allowed_missing_frames: 5,
      allowed_missing_frames_period: 5_000,
      required_on_time_frames: 5,
      signal_specifications: [],
      frame_handlers: [],
      data_length: 0,
      byte_number: 0,
      checksum_required: false,
      checksum_signal_specification: nil
    }
    Map.merge(base, Map.new(overrides))
  end

  def parameter_specification(overrides \\ %{}) do
    base = %ParameterSpecification{
      name: "test_parameter",
      id: 0x0D,
      kind: "integer",
      precision: 2,
      network_name: :test_network,
      request_name: "test_request",
      value_length: 8,
      endianness: "big",
      unit: "km/h",
      scale: D.new(1),
      offset: D.new(0),
      sign: "unsigned"
    }
    Map.merge(base, Map.new(overrides))
  end

  def request_specification(overrides \\ %{}) do
    base = %RequestSpecification{
      name: "test_request",
      request_frame_id: 0x7DF,
      response_frame_id: 0x7E8,
      frequency: 1000,
      mode: 0x01,
      parameter_specifications: [],
      can_interface: "vcan_test"
    }
    Map.merge(base, Map.new(overrides))
  end
end
