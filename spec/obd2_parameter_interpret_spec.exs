defmodule Cantastic.OBD2.ParameterInterpretSpec do
  use ESpec
  alias Cantastic.OBD2.Parameter
  alias Cantastic.TestFactory
  alias Decimal, as: D

  describe ".interpret/3" do
    context "for a decimal parameter" do
      let :spec, do: TestFactory.parameter_specification(%{id: 0x0D, kind: "decimal", value_length: 8, scale: D.new(1)})

      it "decodes the value and returns the remaining bytes" do
        {:ok, parameter, truncated} = Parameter.interpret(<<0x0D, 100, 0xAA, 0xBB>>, spec())
        expect(parameter.value) |> to(eq(D.new("100.00")))
        expect(parameter.raw_value) |> to(eq(<<100>>))
        expect(truncated) |> to(eq(<<0xAA, 0xBB>>))
      end
    end

    context "for an integer parameter with a scale" do
      let :spec, do: TestFactory.parameter_specification(%{id: 0x0C, kind: "integer", value_length: 16, scale: D.new("0.25")})

      it "scales then rounds to an integer" do
        {:ok, parameter, _} = Parameter.interpret(<<0x0C, 0x01, 0x90>>, spec())
        expect(parameter.value) |> to(eq(100))
      end
    end

    context "for an ascii parameter" do
      let :spec, do: TestFactory.parameter_specification(%{id: 0x02, kind: "ascii", value_length: 24})

      it "returns the raw segment as-is" do
        {:ok, parameter, _} = Parameter.interpret(<<0x02, "ABC">>, spec())
        expect(parameter.value) |> to(eq("ABC"))
      end
    end

    context "for a bytes parameter" do
      let :spec, do: TestFactory.parameter_specification(%{id: 0x01, kind: "bytes", value_length: 16})

      it "returns the raw bytes" do
        {:ok, parameter, _} = Parameter.interpret(<<0x01, 0xAB, 0xCD>>, spec())
        expect(parameter.value) |> to(eq(<<0xAB, 0xCD>>))
      end
    end

    context "for a signed little-endian parameter" do
      let :spec,
        do:
          TestFactory.parameter_specification(%{
            id: 0x05,
            kind: "decimal",
            value_length: 8,
            endianness: "little",
            sign: "signed",
            scale: D.new(1)
          })

      it "interprets the two's-complement value" do
        {:ok, parameter, _} = Parameter.interpret(<<0x05, 0xFF>>, spec())
        expect(parameter.value) |> to(eq(D.new("-1.00")))
      end
    end

    context "with a custom id size" do
      let :spec, do: TestFactory.parameter_specification(%{id: 0x0D, kind: "integer", value_length: 8, scale: D.new(1)})

      it "reads the id using the provided bit size" do
        {:ok, parameter, _} = Parameter.interpret(<<0x0D::16, 50>>, spec(), 16)
        expect(parameter.value) |> to(eq(50))
      end
    end

    context "when the parameter id does not match the payload" do
      let :spec, do: TestFactory.parameter_specification(%{id: 0x0D, kind: "integer", value_length: 8})

      it "returns an :error tuple instead of raising" do
        result = Parameter.interpret(<<0x99, 100>>, spec())
        expect(elem(result, 0)) |> to(eq(:error))
      end
    end
  end
end
