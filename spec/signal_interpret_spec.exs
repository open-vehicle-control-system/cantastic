defmodule Cantastic.SignalInterpretSpec do
  use ESpec
  alias Cantastic.Signal
  alias Cantastic.TestFactory
  alias Decimal, as: D

  # `interpret/2` only reads `raw_data` off the frame.
  defp frame(raw_data), do: %{raw_data: raw_data}

  describe ".interpret/2" do
    context "for a decimal signal" do
      let :spec,
        do:
          TestFactory.decimal_signal_specification(%{
            value_start: 0,
            value_length: 16,
            endianness: "big",
            sign: "unsigned",
            scale: D.new(1),
            offset: D.new(0),
            precision: 2
          })

      it "decodes and scales the raw value, rounded to the precision" do
        {:ok, signal} = Signal.interpret(frame(<<0, 100>>), spec())
        expect(signal.value) |> to(eq(D.new("100.00")))
        expect(signal.raw_value) |> to(eq(<<0, 100>>))
        expect(signal.kind) |> to(eq("decimal"))
      end

      it "applies scale and offset" do
        spec = %{spec() | scale: D.new(2), offset: D.new("10")}
        {:ok, signal} = Signal.interpret(frame(<<0, 5>>), spec)
        expect(signal.value) |> to(eq(D.new("20.00")))
      end
    end

    context "for an integer signal" do
      let :spec,
        do:
          TestFactory.integer_signal_specification(%{
            value_start: 0,
            value_length: 8,
            endianness: "big",
            sign: "unsigned",
            scale: D.new(2),
            offset: D.new(0)
          })

      it "returns a rounded integer value" do
        {:ok, signal} = Signal.interpret(frame(<<10>>), spec())
        expect(signal.value) |> to(eq(20))
      end
    end

    context "for a signed signal" do
      let :spec,
        do:
          TestFactory.decimal_signal_specification(%{
            value_start: 0,
            value_length: 8,
            endianness: "big",
            sign: "signed",
            scale: D.new(1),
            offset: D.new(0),
            precision: 2
          })

      it "interprets the two's-complement value" do
        {:ok, signal} = Signal.interpret(frame(<<0xFF>>), spec())
        expect(signal.value) |> to(eq(D.new("-1.00")))
      end
    end

    context "for an enum signal" do
      let :spec,
        do: TestFactory.enum_signal_specification(%{0 => "off", 1 => "on"}, 8, %{value_start: 0})

      it "maps the raw value through the mapping" do
        {:ok, signal} = Signal.interpret(frame(<<1>>), spec())
        expect(signal.value) |> to(eq("on"))
      end
    end

    context "for a static signal" do
      let :spec, do: TestFactory.static_signal_specification(0xAB, 8, %{value_start: 0})

      it "returns the raw segment verbatim" do
        {:ok, signal} = Signal.interpret(frame(<<0xAB>>), spec())
        expect(signal.value) |> to(eq(<<0xAB>>))
      end
    end

    context "when the value is described by several ranges" do
      let :spec,
        do:
          TestFactory.decimal_signal_specification(%{
            value_start: [%{start: 0, length: 8}, %{start: 8, length: 8}],
            value_length: 16,
            endianness: "big",
            sign: "unsigned",
            scale: D.new(1),
            offset: D.new(0),
            precision: 2
          })

      it "concatenates the segments into the raw value" do
        {:ok, signal} = Signal.interpret(frame(<<0x01, 0x02>>), spec())
        expect(byte_size(signal.raw_value)) |> to(eq(2))
      end
    end
  end

  describe ".build_raw/2" do
    it "looks an enum value up through the reverse mapping" do
      spec = TestFactory.enum_signal_specification(%{1 => "on"}, 8)
      expect(Signal.build_raw(spec, "on")) |> to(eq(<<1>>))
    end

    it "returns an empty binary for a checksum signal" do
      spec = TestFactory.integer_signal_specification(%{kind: "checksum"})
      expect(Signal.build_raw(spec, 0)) |> to(eq(<<>>))
    end

    it "encodes a signed big-endian decimal" do
      spec =
        TestFactory.decimal_signal_specification(%{
          endianness: "big",
          sign: "signed",
          value_length: 8,
          scale: D.new(1),
          offset: D.new(0)
        })

      expect(Signal.build_raw(spec, D.new(-1))) |> to(eq(<<0xFF>>))
    end

    it "encodes a signed little-endian integer" do
      spec =
        TestFactory.integer_signal_specification(%{
          endianness: "little",
          sign: "signed",
          value_length: 16,
          scale: D.new(1),
          offset: D.new(0)
        })

      expect(Signal.build_raw(spec, -2)) |> to(eq(<<-2::little-signed-integer-size(16)>>))
    end
  end
end
