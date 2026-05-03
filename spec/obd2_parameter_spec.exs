defmodule Cantastic.OBD2.ParameterSpec do
  use ESpec
  alias Cantastic.OBD2.Parameter
  alias Decimal, as: D

  describe "rendering an OBD2 parameter for debugging" do
    context "with an integer value" do
      let :parameter, do: %Parameter{
        request_name: "current_speed",
        name: "speed",
        kind: "integer",
        value: 50,
        unit: "km/h"
      }

      it "produces a one-line representation including request name, parameter name, and value" do
        expect(Parameter.to_string(parameter())) |> to(eq("[OBD2 Parameter] current_speed.speed = 50"))
      end
    end

    context "with a decimal value" do
      let :parameter, do: %Parameter{
        request_name: "current_speed",
        name: "rpm",
        kind: "decimal",
        value: D.new("625.00"),
        unit: "rpm"
      }

      it "produces a one-line representation with the formatted decimal" do
        expect(Parameter.to_string(parameter())) |> to(eq("[OBD2 Parameter] current_speed.rpm = 625.00"))
      end
    end
  end
end
