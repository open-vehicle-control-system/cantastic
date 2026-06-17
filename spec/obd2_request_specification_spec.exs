defmodule Cantastic.OBD2.RequestSpecificationSpec do
  use ESpec
  alias Cantastic.OBD2.RequestSpecification

  defp thrown(fun) do
    try do
      fun.()
      :no_throw
    catch
      value -> value
    end
  end

  describe ".from_yaml/3" do
    context "with a request carrying parameters" do
      let :yaml,
        do: %{
          name: "current_speed",
          request_frame_id: 0x7DF,
          response_frame_id: 0x7E8,
          frequency: 1000,
          mode: 0x01,
          parameters: [%{name: "speed", id: 0x0D, value_length: 8}]
        }

      let :spec, do: (fn -> {:ok, s} = RequestSpecification.from_yaml(:diag, "vcan0", yaml()); s end).()

      it "builds the request and its nested parameter specifications" do
        expect(spec().name) |> to(eq("current_speed"))
        expect(spec().mode) |> to(eq(0x01))
        expect(spec().can_interface) |> to(eq("vcan0"))
        expect(length(spec().parameter_specifications)) |> to(eq(1))
        [param] = spec().parameter_specifications
        expect(param.name) |> to(eq("speed"))
        expect(param.request_name) |> to(eq("current_speed"))
      end

      it "defaults options to an empty map" do
        expect(spec().options) |> to(eq(%{}))
      end
    end

    context "with no parameters" do
      let :yaml,
        do: %{
          name: "session",
          request_frame_id: 0x7E0,
          response_frame_id: 0x7E8,
          frequency: 1000,
          mode: 0x10
        }

      it "builds a request with an empty parameter list" do
        {:ok, spec} = RequestSpecification.from_yaml(:diag, "vcan0", yaml())
        expect(spec.parameter_specifications) |> to(eq([]))
      end
    end

    context "with an unauthorized key" do
      let :yaml,
        do: %{
          name: "x",
          request_frame_id: 0x7DF,
          response_frame_id: 0x7E8,
          frequency: 1,
          mode: 1,
          bogus: 1
        }

      it "throws a configuration error" do
        message = thrown(fn -> RequestSpecification.from_yaml(:diag, "vcan0", yaml()) end)
        expect(String.contains?(message, "invalid key")) |> to(eq(true))
      end
    end
  end

  describe ".validate_specification!/1" do
    let :base,
      do: %RequestSpecification{
        name: "req",
        request_frame_id: 0x7DF,
        response_frame_id: 0x7E8,
        frequency: 1000,
        mode: 0x01,
        parameter_specifications: []
      }

    it "passes for a valid specification" do
      expect(thrown(fn -> RequestSpecification.validate_specification!(base()) end)) |> to(eq(:no_throw))
    end

    it "throws when the name is missing" do
      message = thrown(fn -> RequestSpecification.validate_specification!(%{base() | name: nil}) end)
      expect(String.contains?(message, "missing a 'name'")) |> to(eq(true))
    end

    it "throws when request_frame_id is missing" do
      message = thrown(fn -> RequestSpecification.validate_specification!(%{base() | request_frame_id: nil}) end)
      expect(String.contains?(message, "missing an 'request_frame_id'")) |> to(eq(true))
    end

    it "throws when response_frame_id is missing" do
      message = thrown(fn -> RequestSpecification.validate_specification!(%{base() | response_frame_id: nil}) end)
      expect(String.contains?(message, "missing an 'response_frame_id'")) |> to(eq(true))
    end
  end
end
