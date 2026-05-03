defmodule Cantastic.SignalSpecificationSpec do
  use ESpec
  alias Cantastic.SignalSpecification
  alias Decimal, as: D

  describe ".from_yaml/4" do
    let :network_name, do: :test_network
    let :frame_id, do: 0x100
    let :frame_name, do: "test_frame"
    let :result, do: SignalSpecification.from_yaml(network_name(), frame_id(), frame_name(), yaml())

    context "with the minimum required keys" do
      let :yaml, do: %{name: "speed", value_start: 0, value_length: 8}

      it "returns a populated specification with sensible defaults" do
        {:ok, spec} = result()
        expect(spec.name) |> to(eq("speed"))
        expect(spec.network_name) |> to(eq(:test_network))
        expect(spec.frame_id) |> to(eq(0x100))
        expect(spec.frame_name) |> to(eq("test_frame"))
        expect(spec.kind) |> to(eq("decimal"))
        expect(spec.precision) |> to(eq(2))
        expect(spec.sign) |> to(eq("unsigned"))
        expect(spec.endianness) |> to(eq("little"))
        expect(spec.value_start) |> to(eq(0))
        expect(spec.value_length) |> to(eq(8))
        expect(spec.scale) |> to(eq(D.new("1")))
        expect(spec.offset) |> to(eq(D.new("0")))
        expect(spec.unit) |> to(be_nil())
        expect(spec.mapping) |> to(be_nil())
        expect(spec.reverse_mapping) |> to(be_nil())
      end
    end

    context "with explicit overrides" do
      let :yaml, do: %{
        name: "rpm",
        kind: "integer",
        precision: 3,
        sign: "signed",
        value_start: 16,
        value_length: 16,
        endianness: "big",
        unit: "RPM",
        scale: "0.25",
        offset: "10"
      }

      it "uses each provided value" do
        {:ok, spec} = result()
        expect(spec.kind) |> to(eq("integer"))
        expect(spec.precision) |> to(eq(3))
        expect(spec.sign) |> to(eq("signed"))
        expect(spec.endianness) |> to(eq("big"))
        expect(spec.unit) |> to(eq("RPM"))
        expect(spec.scale) |> to(eq(D.new("0.25")))
        expect(spec.offset) |> to(eq(D.new("10")))
      end
    end

    context "for an enum kind with a mapping" do
      let :yaml, do: %{
        name: "gear",
        kind: "enum",
        value_start: 0,
        value_length: 8,
        mapping: %{:"0" => "drive", :"1" => "neutral", :"2" => "reverse"}
      }

      it "computes a mapping keyed by big-endian raw bytes" do
        {:ok, spec} = result()
        expect(spec.mapping[<<0x00>>]) |> to(eq("drive"))
        expect(spec.mapping[<<0x01>>]) |> to(eq("neutral"))
        expect(spec.mapping[<<0x02>>]) |> to(eq("reverse"))
      end

      it "computes a reverse mapping keyed by the named values" do
        {:ok, spec} = result()
        expect(spec.reverse_mapping["drive"]) |> to(eq(<<0x00>>))
        expect(spec.reverse_mapping["neutral"]) |> to(eq(<<0x01>>))
        expect(spec.reverse_mapping["reverse"]) |> to(eq(<<0x02>>))
      end
    end

    context "for a static kind with an explicit value" do
      let :yaml, do: %{name: "filler", kind: "static", value_start: 0, value_length: 8, value: 0xAB}

      it "encodes the static value to a big-endian binary of value_length bits" do
        {:ok, spec} = result()
        expect(spec.value) |> to(eq(<<0xAB>>))
      end
    end

    context "with an unknown YAML key" do
      let :yaml, do: %{name: "speed", value_start: 0, value_length: 8, foo: "bar"}

      it "throws a configuration error" do
        expect(fn -> result() end) |> to(throw_term())
      end
    end
  end

  describe ".validate_specification!/1" do
    let :spec, do: %SignalSpecification{
      name: "speed",
      network_name: :test_network,
      frame_id: 0x100,
      frame_name: "test_frame",
      kind: "integer",
      sign: "unsigned",
      endianness: "little",
      value_start: 0,
      value_length: 8,
      scale: D.new(1),
      offset: D.new(0)
    }

    it "passes for a valid specification" do
      expect(fn -> SignalSpecification.validate_specification!(spec()) end) |> to_not(throw_term())
    end

    it "throws when name is missing" do
      expect(fn -> SignalSpecification.validate_specification!(%{spec() | name: nil}) end)
      |> to(throw_term())
    end

    it "throws when value_start is missing" do
      expect(fn -> SignalSpecification.validate_specification!(%{spec() | value_start: nil}) end)
      |> to(throw_term())
    end

    it "throws when value_length is missing" do
      expect(fn -> SignalSpecification.validate_specification!(%{spec() | value_length: nil}) end)
      |> to(throw_term())
    end

    it "throws on an invalid kind" do
      expect(fn -> SignalSpecification.validate_specification!(%{spec() | kind: "bogus"}) end)
      |> to(throw_term())
    end

    it "throws on an invalid sign" do
      expect(fn -> SignalSpecification.validate_specification!(%{spec() | sign: "bogus"}) end)
      |> to(throw_term())
    end

    it "throws on an invalid endianness" do
      expect(fn -> SignalSpecification.validate_specification!(%{spec() | endianness: "bogus"}) end)
      |> to(throw_term())
    end

    it "throws when an enum kind has no mapping" do
      bad = %{spec() | kind: "enum", mapping: nil}
      expect(fn -> SignalSpecification.validate_specification!(bad) end) |> to(throw_term())
    end

    it "throws when a static kind has no value" do
      bad = %{spec() | kind: "static", value: nil}
      expect(fn -> SignalSpecification.validate_specification!(bad) end) |> to(throw_term())
    end
  end
end
