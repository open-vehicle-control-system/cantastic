defmodule Cantastic.TestFactory do
  alias Cantastic.{SignalSpecification}
  alias Decimal, as: D

  def integer_signal_specification do
    %SignalSpecification{
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
  end
end
