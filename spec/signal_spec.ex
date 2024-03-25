defmodule Cantastic.SignalSpec do
  use ESpec
  alias Cantastic.{Signal, SignalSpecification}
  alias Decimal, as: D

  describe ".to_string/1" do

    let :signal, do: %Signal{name: "SignalName", frame_name: "FrameName", value: value(), unit: "M", kind: kind()}
    let :result, do: Signal.to_string(signal())

    context "For integer signal values" do
      let :value, do: 111
      let :kind, do: "integer"

      it "returns a valid string including the signal name, frame name and value" do
        expect(result()) |> to(eq("[Signal] FrameName.SignalName = 111"))
      end
    end
  end

  describe ".build_raw(raw_data, signal_specification, value)" do
    let :result, do: Signal.build_raw(raw_data(), signal_specification(), value())
    let :signal_specification, do: %SignalSpecification{
      kind: kind(),
      scale: scale(),
      offset: offset(),
      value_length: value_length(),
      endianness: endianness()
    }

    context "for an integer kind" do
      let :kind, do: "integer"

      context "and a little endianess" do
        let endianness: "little"

        context "and a scale of 1" do
          let :scale, do: D.new(1)

          context "and an offset of 0" do
            let :offset, do: D.new(0)

            context "and a value length of 16" do
              let :value_length, do: 16

              context "and a value independent of the previous raw data" do
                let :raw_data, do: <<>>
                let :value, do: Faker.random_between(0, 1000)

                it "returns the bitstring representation of the integer" do
                  expect(result()) |> to(eq(<<value()::little-integer-size(16)>>))
                end
              end
            end
          end
        end
      end

      context "and a big endianess" do
        let endianness: "big"

        context "and a scale of 1" do
          let :scale, do: D.new(1)

          context "and an offset of 0" do
            let :offset, do: D.new(0)

            context "and a value length of 8" do
              let :value_length, do: 16

              context "and a value independent of the previous raw data" do
                let :raw_data, do: <<>>
                let :value, do: Faker.random_between(0, 1000)

                it "returns the bitstring representation of the integer" do
                  expect(result()) |> to(eq(<<value()::big-integer-size(16)>>))
                end
              end
            end
          end
        end
      end
    end
  end
end
