defmodule Cantastic.SignalSpecificationSpec do
  use ESpec
  alias Cantastic.SignalSpecification
  alias Decimal, as: D

  # Captures a `throw` so we can assert on the configuration-error message
  # without ESpec needing a dedicated throw matcher.
  defp thrown(fun) do
    try do
      fun.()
      :no_throw
    catch
      value -> value
    end
  end

  describe ".from_yaml/4" do
    context "with a minimal signal" do
      let :yaml, do: %{name: "rpm", value_start: 0, value_length: 16}
      let :spec, do: (fn -> {:ok, s} = SignalSpecification.from_yaml(:powertrain, 0x100, "engine", yaml()); s end).()

      it "applies sensible defaults" do
        expect(spec().kind) |> to(eq("decimal"))
        expect(spec().precision) |> to(eq(2))
        expect(spec().sign) |> to(eq("unsigned"))
        expect(spec().endianness) |> to(eq("little"))
        expect(spec().scale) |> to(eq(D.new("1")))
        expect(spec().offset) |> to(eq(D.new("0")))
        expect(spec().mapping) |> to(eq(nil))
        expect(spec().reverse_mapping) |> to(eq(nil))
      end

      it "carries the network, frame id and frame name through" do
        expect(spec().network_name) |> to(eq(:powertrain))
        expect(spec().frame_id) |> to(eq(0x100))
        expect(spec().frame_name) |> to(eq("engine"))
        expect(spec().value_start) |> to(eq(0))
        expect(spec().value_length) |> to(eq(16))
      end
    end

    context "with explicit overrides" do
      let :yaml,
        do: %{
          name: "temp",
          kind: "integer",
          precision: 0,
          sign: "signed",
          value_start: 8,
          value_length: 8,
          endianness: "big",
          unit: "C",
          scale: "0.5",
          offset: "-40"
        }

      it "uses the provided values" do
        {:ok, spec} = SignalSpecification.from_yaml(:body, 1, "climate", yaml())
        expect(spec.kind) |> to(eq("integer"))
        expect(spec.sign) |> to(eq("signed"))
        expect(spec.endianness) |> to(eq("big"))
        expect(spec.unit) |> to(eq("C"))
        expect(spec.scale) |> to(eq(D.new("0.5")))
        expect(spec.offset) |> to(eq(D.new("-40")))
      end
    end

    context "with an enum mapping" do
      let :yaml,
        do: %{
          name: "gear",
          kind: "enum",
          value_start: 0,
          value_length: 8,
          mapping: %{"0": "park", "1": "drive"}
        }

      it "computes a binary-keyed mapping and its reverse" do
        {:ok, spec} = SignalSpecification.from_yaml(:t, 1, "f", yaml())
        expect(spec.mapping[<<0::big-integer-size(8)>>]) |> to(eq("park"))
        expect(spec.mapping[<<1::big-integer-size(8)>>]) |> to(eq("drive"))
        expect(spec.reverse_mapping["drive"]) |> to(eq(<<1::big-integer-size(8)>>))
        expect(spec.reverse_mapping["park"]) |> to(eq(<<0::big-integer-size(8)>>))
      end
    end

    context "with a static value" do
      let :yaml, do: %{name: "filler", kind: "static", value: 0xAB, value_start: 0, value_length: 8}

      it "stores the value as a big-endian binary" do
        {:ok, spec} = SignalSpecification.from_yaml(:t, 1, "f", yaml())
        expect(spec.value) |> to(eq(<<0xAB::big-integer-size(8)>>))
      end
    end

    context "with an unauthorized key" do
      let :yaml, do: %{name: "x", value_start: 0, value_length: 8, bogus: 1}

      it "throws a configuration error naming the invalid key" do
        message = thrown(fn -> SignalSpecification.from_yaml(:t, 1, "f", yaml()) end)
        expect(String.contains?(message, "invalid keys")) |> to(eq(true))
        expect(String.contains?(message, "bogus")) |> to(eq(true))
      end
    end
  end

  describe ".validate_specification!/1" do
    let :base,
      do: %SignalSpecification{
        name: "s",
        network_name: :t,
        frame_name: "f",
        value_start: 0,
        value_length: 8,
        kind: "integer",
        sign: "unsigned",
        endianness: "little"
      }

    it "passes for a valid specification" do
      expect(thrown(fn -> SignalSpecification.validate_specification!(base()) end)) |> to(eq(:no_throw))
    end

    it "throws when the name is missing" do
      spec = %{base() | name: nil}
      message = thrown(fn -> SignalSpecification.validate_specification!(spec) end)
      expect(String.contains?(message, "missing a 'name'")) |> to(eq(true))
    end

    it "throws when value_start is missing" do
      spec = %{base() | value_start: nil}
      message = thrown(fn -> SignalSpecification.validate_specification!(spec) end)
      expect(String.contains?(message, "missing a 'value_start'")) |> to(eq(true))
    end

    it "throws when value_length is missing" do
      spec = %{base() | value_length: nil}
      message = thrown(fn -> SignalSpecification.validate_specification!(spec) end)
      expect(String.contains?(message, "missing a 'value_length'")) |> to(eq(true))
    end

    it "throws on an invalid kind" do
      spec = %{base() | kind: "bogus"}
      message = thrown(fn -> SignalSpecification.validate_specification!(spec) end)
      expect(String.contains?(message, "invalid kind")) |> to(eq(true))
    end

    it "throws on an invalid sign" do
      spec = %{base() | sign: "weird"}
      message = thrown(fn -> SignalSpecification.validate_specification!(spec) end)
      expect(String.contains?(message, "invalid sign")) |> to(eq(true))
    end

    it "throws on an invalid endianness" do
      spec = %{base() | endianness: "sideways"}
      message = thrown(fn -> SignalSpecification.validate_specification!(spec) end)
      expect(String.contains?(message, "invalid endianness")) |> to(eq(true))
    end

    it "throws when an enum signal has no mapping" do
      spec = %{base() | kind: "enum", mapping: %{}}
      message = thrown(fn -> SignalSpecification.validate_specification!(spec) end)
      expect(String.contains?(message, "mapping is missing")) |> to(eq(true))
    end

    it "throws when a static signal has no value" do
      spec = %{base() | kind: "static", value: nil}
      message = thrown(fn -> SignalSpecification.validate_specification!(spec) end)
      expect(String.contains?(message, "value is missing")) |> to(eq(true))
    end
  end
end
