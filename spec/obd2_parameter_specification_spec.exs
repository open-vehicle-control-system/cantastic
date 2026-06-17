defmodule Cantastic.OBD2.ParameterSpecificationSpec do
  use ESpec
  alias Cantastic.OBD2.ParameterSpecification
  alias Decimal, as: D

  defp thrown(fun) do
    try do
      fun.()
      :no_throw
    catch
      value -> value
    end
  end

  describe ".from_yaml/3" do
    context "with a minimal parameter" do
      let :yaml, do: %{name: "speed", id: 0x0D, value_length: 8}

      it "applies sensible defaults" do
        {:ok, spec} = ParameterSpecification.from_yaml(:diag, "current_speed", yaml())
        expect(spec.kind) |> to(eq("decimal"))
        expect(spec.precision) |> to(eq(2))
        expect(spec.sign) |> to(eq("unsigned"))
        expect(spec.endianness) |> to(eq("big"))
        expect(spec.scale) |> to(eq(D.new("1")))
        expect(spec.offset) |> to(eq(D.new("0")))
        expect(spec.network_name) |> to(eq(:diag))
        expect(spec.request_name) |> to(eq("current_speed"))
      end
    end

    context "with overrides" do
      let :yaml,
        do: %{
          name: "rpm",
          id: 0x0C,
          kind: "integer",
          sign: "signed",
          value_length: 16,
          endianness: "little",
          unit: "rpm",
          scale: "0.25",
          offset: "0"
        }

      it "uses the provided values" do
        {:ok, spec} = ParameterSpecification.from_yaml(:diag, "engine", yaml())
        expect(spec.kind) |> to(eq("integer"))
        expect(spec.sign) |> to(eq("signed"))
        expect(spec.endianness) |> to(eq("little"))
        expect(spec.scale) |> to(eq(D.new("0.25")))
        expect(spec.unit) |> to(eq("rpm"))
      end
    end

    context "with an unauthorized key" do
      let :yaml, do: %{name: "x", id: 1, value_length: 8, bogus: 1}

      it "throws a configuration error" do
        message = thrown(fn -> ParameterSpecification.from_yaml(:diag, "req", yaml()) end)
        expect(String.contains?(message, "invalid keys")) |> to(eq(true))
      end
    end
  end

  describe ".validate_specification!/1" do
    let :base,
      do: %ParameterSpecification{
        name: "p",
        id: 0x0D,
        network_name: :diag,
        request_name: "req",
        value_length: 8,
        kind: "integer",
        sign: "unsigned",
        endianness: "big"
      }

    it "passes for a valid specification" do
      expect(thrown(fn -> ParameterSpecification.validate_specification!(base()) end)) |> to(eq(:no_throw))
    end

    it "throws when the name is missing" do
      message = thrown(fn -> ParameterSpecification.validate_specification!(%{base() | name: nil}) end)
      expect(String.contains?(message, "missing a 'name'")) |> to(eq(true))
    end

    it "throws when the id is missing" do
      message = thrown(fn -> ParameterSpecification.validate_specification!(%{base() | id: nil}) end)
      expect(String.contains?(message, "missing an 'id'")) |> to(eq(true))
    end

    it "throws when value_length is missing" do
      message = thrown(fn -> ParameterSpecification.validate_specification!(%{base() | value_length: nil}) end)
      expect(String.contains?(message, "missing a 'value_length'")) |> to(eq(true))
    end

    it "throws on an invalid kind" do
      message = thrown(fn -> ParameterSpecification.validate_specification!(%{base() | kind: "bogus"}) end)
      expect(String.contains?(message, "invalid kind")) |> to(eq(true))
    end

    it "throws on an invalid sign" do
      message = thrown(fn -> ParameterSpecification.validate_specification!(%{base() | sign: "weird"}) end)
      expect(String.contains?(message, "invalid sign")) |> to(eq(true))
    end

    it "throws on an invalid endianness" do
      message = thrown(fn -> ParameterSpecification.validate_specification!(%{base() | endianness: "sideways"}) end)
      expect(String.contains?(message, "invalid endianness")) |> to(eq(true))
    end
  end
end
