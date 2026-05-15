defmodule Cantastic.SignalSpec do
  use ESpec
  alias Cantastic.{Signal, SignalSpecification}
  alias Decimal, as: D

  describe ".to_string/1" do
    let :signal,
      do: %Signal{
        name: "SignalName",
        frame_name: "FrameName",
        value: value(),
        unit: "M",
        kind: kind()
      }

    let :result, do: Signal.to_string(signal())

    context "For integer signal values" do
      let :value, do: 111
      let :kind, do: "integer"

      it "returns a valid string including the signal name, frame name and value" do
        expect(result()) |> to(eq("[Signal] FrameName.SignalName = 111"))
      end
    end
  end

  describe ".build_raw/2" do
    let :signal_specification,
      do: %SignalSpecification{
        kind: kind(),
        scale: scale(),
        offset: offset(),
        value_length: value_length(),
        endianness: endianness(),
        sign: sign()
      }

    let :result, do: Signal.build_raw(signal_specification(), value())
    let :scale, do: D.new(1)
    let :offset, do: D.new(0)
    let :value_length, do: 16
    let :sign, do: "unsigned"

    context "for an integer kind, little endianness, scale 1, offset 0, length 16" do
      let :kind, do: "integer"
      let :endianness, do: "little"
      let :value, do: 510

      it "returns the bitstring representation of the integer" do
        expect(result()) |> to(eq(<<value()::little-unsigned-integer-size(16)>>))
      end
    end

    context "for an integer kind, big endianness, scale 1, offset 0, length 16" do
      let :kind, do: "integer"
      let :endianness, do: "big"
      let :value, do: 510

      it "returns the bitstring representation of the integer" do
        expect(result()) |> to(eq(<<value()::big-unsigned-integer-size(16)>>))
      end
    end

    context "for a static kind the value field is returned verbatim" do
      let :kind, do: "static"
      let :endianness, do: nil
      let :signal_specification,
        do: %SignalSpecification{kind: "static", value: <<0xAB, 0xCD>>}

      let :value, do: :ignored

      it "returns the stored static value" do
        expect(result()) |> to(eq(<<0xAB, 0xCD>>))
      end
    end
  end
end
