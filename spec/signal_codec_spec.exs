defmodule Cantastic.SignalCodecSpec do
  use ESpec
  alias Cantastic.{Frame, Signal, SignalSpecification}
  alias Decimal, as: D

  defp spec_with(overrides) do
    base = %SignalSpecification{
      name: "test_signal",
      network_name: :test_network,
      frame_id: 0x100,
      frame_name: "test_frame",
      kind: "decimal",
      precision: 2,
      sign: "unsigned",
      endianness: "little",
      value_start: 0,
      value_length: 8,
      scale: D.new(1),
      offset: D.new(0),
      mapping: nil,
      reverse_mapping: nil
    }
    Map.merge(base, Map.new(overrides))
  end

  defp frame_with(raw_data) do
    %Frame{
      id: 0x100,
      name: "test_frame",
      network_name: :test_network,
      raw_data: raw_data,
      byte_number: byte_size(raw_data)
    }
  end

  describe ".interpret/2" do
    context "for an unsigned little-endian integer" do
      let :spec, do: spec_with(%{kind: "integer", sign: "unsigned", endianness: "little", value_length: 16})
      let :frame, do: frame_with(<<0x32, 0x00>>)

      it "decodes from the raw bytes" do
        {:ok, signal} = Signal.interpret(frame(), spec())
        expect(signal.value) |> to(eq(50))
      end
    end

    context "for an unsigned big-endian integer" do
      let :spec, do: spec_with(%{kind: "integer", sign: "unsigned", endianness: "big", value_length: 16})
      let :frame, do: frame_with(<<0x12, 0x34>>)

      it "decodes from the raw bytes" do
        {:ok, signal} = Signal.interpret(frame(), spec())
        expect(signal.value) |> to(eq(0x1234))
      end
    end

    context "for a signed integer" do
      let :spec, do: spec_with(%{kind: "integer", sign: "signed", endianness: "little", value_length: 8})
      let :frame, do: frame_with(<<0xFF>>)

      it "decodes negative numbers correctly" do
        {:ok, signal} = Signal.interpret(frame(), spec())
        expect(signal.value) |> to(eq(-1))
      end
    end

    context "for a decimal with scale and offset" do
      let :spec, do: spec_with(%{kind: "decimal", endianness: "little", value_length: 8, scale: D.new("0.5"), offset: D.new("10"), precision: 2})
      let :frame, do: frame_with(<<0x14>>)

      it "applies scale * raw + offset" do
        {:ok, signal} = Signal.interpret(frame(), spec())
        expect(D.eq?(signal.value, D.new("20.0"))) |> to(be_true())
      end

      it "rounds to the configured precision" do
        spec = spec_with(%{kind: "decimal", endianness: "little", value_length: 8, scale: D.new("0.333"), offset: D.new("0"), precision: 1})
        {:ok, signal} = Signal.interpret(frame_with(<<0x03>>), spec)
        expect(D.eq?(signal.value, D.new("1.0"))) |> to(be_true())
      end
    end

    context "for an enum kind" do
      let :spec, do: spec_with(%{
        kind: "enum",
        value_length: 8,
        mapping: %{<<0x00>> => "drive", <<0x01>> => "neutral", <<0x02>> => "reverse"}
      })

      it "looks up the value by raw bytes" do
        {:ok, signal} = Signal.interpret(frame_with(<<0x01>>), spec())
        expect(signal.value) |> to(eq("neutral"))
      end

      it "returns nil for an unmapped raw value" do
        {:ok, signal} = Signal.interpret(frame_with(<<0x09>>), spec())
        expect(signal.value) |> to(be_nil())
      end
    end

    context "for a static kind" do
      let :spec, do: spec_with(%{kind: "static", value_length: 8})

      it "returns the raw bytes verbatim as the value" do
        {:ok, signal} = Signal.interpret(frame_with(<<0xAB>>), spec())
        expect(signal.value) |> to(eq(<<0xAB>>))
      end
    end

    context "with a non-zero value_start" do
      let :spec, do: spec_with(%{kind: "integer", sign: "unsigned", endianness: "big", value_start: 8, value_length: 8})

      it "extracts from the configured offset" do
        {:ok, signal} = Signal.interpret(frame_with(<<0x00, 0x42>>), spec())
        expect(signal.value) |> to(eq(0x42))
      end
    end

    context "populates struct fields" do
      let :spec, do: spec_with(%{kind: "integer", endianness: "little", value_length: 8, unit: "RPM"})

      it "carries name, frame_name, kind, unit, raw_value" do
        {:ok, signal} = Signal.interpret(frame_with(<<0x05>>), spec())
        expect(signal.name) |> to(eq("test_signal"))
        expect(signal.frame_name) |> to(eq("test_frame"))
        expect(signal.kind) |> to(eq("integer"))
        expect(signal.unit) |> to(eq("RPM"))
        expect(signal.raw_value) |> to(eq(<<0x05>>))
      end
    end
  end

  describe ".build_raw/2" do
    context "for an integer little-endian unsigned" do
      let :spec, do: spec_with(%{kind: "integer", sign: "unsigned", endianness: "little", value_length: 16})

      it "encodes the integer in little-endian" do
        expect(Signal.build_raw(spec(), 50)) |> to(eq(<<0x32, 0x00>>))
      end
    end

    context "for an integer big-endian unsigned" do
      let :spec, do: spec_with(%{kind: "integer", sign: "unsigned", endianness: "big", value_length: 16})

      it "encodes the integer in big-endian" do
        expect(Signal.build_raw(spec(), 0x1234)) |> to(eq(<<0x12, 0x34>>))
      end
    end

    context "for a signed integer" do
      let :spec, do: spec_with(%{kind: "integer", sign: "signed", endianness: "little", value_length: 8})

      it "encodes negative values" do
        expect(Signal.build_raw(spec(), -1)) |> to(eq(<<0xFF>>))
      end
    end

    context "for a decimal with scale and offset" do
      let :spec, do: spec_with(%{kind: "decimal", endianness: "little", value_length: 8, scale: D.new("0.5"), offset: D.new("10")})

      it "applies (value - offset) / scale before encoding" do
        expect(Signal.build_raw(spec(), D.new("20"))) |> to(eq(<<0x14>>))
      end
    end

    context "for an enum kind" do
      let :spec, do: spec_with(%{
        kind: "enum",
        value_length: 8,
        reverse_mapping: %{"drive" => <<0x00>>, "neutral" => <<0x01>>, "reverse" => <<0x02>>}
      })

      it "looks up the raw bytes from the reverse mapping" do
        expect(Signal.build_raw(spec(), "neutral")) |> to(eq(<<0x01>>))
      end

      it "returns nil for an unknown value" do
        expect(Signal.build_raw(spec(), "park")) |> to(be_nil())
      end
    end

    context "for a static kind" do
      let :spec, do: spec_with(%{kind: "static", value_length: 8, value: <<0xAB>>})

      it "returns the configured static raw value, ignoring the input" do
        expect(Signal.build_raw(spec(), 999)) |> to(eq(<<0xAB>>))
      end
    end

    context "for a checksum kind" do
      let :spec, do: spec_with(%{kind: "checksum", value_length: 8})

      it "returns an empty bitstring (the checksum is inserted later)" do
        expect(Signal.build_raw(spec(), nil)) |> to(eq(<<>>))
      end
    end
  end

  describe ".to_string/1" do
    it "formats decimal signals with frame and value" do
      signal = %Signal{name: "speed", frame_name: "obd2", value: D.new("25.5"), unit: "km/h", kind: "decimal"}
      expect(Signal.to_string(signal)) |> to(eq("[Signal] obd2.speed = 25.5"))
    end
  end
end
