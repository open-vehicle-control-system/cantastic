defmodule Cantastic.FrameSpecificationSpec do
  use ESpec
  alias Cantastic.FrameSpecification

  defp thrown(fun) do
    try do
      fun.()
      :no_throw
    catch
      value -> value
    end
  end

  describe ".from_yaml/3 for a received frame" do
    let :yaml,
      do: %{
        id: 0x100,
        name: "engine",
        signals: [
          %{name: "rpm", value_start: 0, value_length: 16},
          %{name: "temp", value_start: 16, value_length: 8}
        ]
      }

    let :spec, do: (fn -> {:ok, s} = FrameSpecification.from_yaml(:powertrain, yaml(), :receive); s end).()

    it "carries id, name and network through" do
      expect(spec().id) |> to(eq(0x100))
      expect(spec().name) |> to(eq("engine"))
      expect(spec().network_name) |> to(eq(:powertrain))
    end

    it "computes the total data length and byte number from the signals" do
      expect(spec().data_length) |> to(eq(24))
      expect(spec().byte_number) |> to(eq(3))
    end

    it "builds one signal specification per signal" do
      expect(length(spec().signal_specifications)) |> to(eq(2))
    end

    it "applies the documented defaults" do
      expect(spec().allowed_frequency_leeway) |> to(eq(10))
      expect(spec().allowed_missing_frames) |> to(eq(5))
      expect(spec().allowed_missing_frames_period) |> to(eq(5_000))
      expect(spec().required_on_time_frames) |> to(eq(5))
      expect(spec().checksum_required) |> to(eq(false))
      expect(spec().checksum_signal_specification) |> to(eq(nil))
    end
  end

  describe ".from_yaml/3 checksum handling" do
    it "flags the frame as requiring a checksum when one checksum signal is present" do
      yaml = %{
        id: 1,
        name: "f",
        signals: [
          %{name: "data", value_start: 0, value_length: 8},
          %{name: "crc", kind: "checksum", value_start: 8, value_length: 8}
        ]
      }

      {:ok, spec} = FrameSpecification.from_yaml(:t, yaml, :receive)
      expect(spec.checksum_required) |> to(eq(true))
      expect(spec.checksum_signal_specification.name) |> to(eq("crc"))
    end

    it "throws when more than one checksum signal is defined" do
      yaml = %{
        id: 1,
        name: "f",
        signals: [
          %{name: "crc1", kind: "checksum", value_start: 0, value_length: 8},
          %{name: "crc2", kind: "checksum", value_start: 8, value_length: 8}
        ]
      }

      message = thrown(fn -> FrameSpecification.from_yaml(:t, yaml, :receive) end)
      expect(String.contains?(message, "more than one checksum")) |> to(eq(true))
    end
  end

  describe ".from_yaml/3 validation" do
    it "throws on an unauthorized frame key" do
      yaml = %{id: 1, name: "f", signals: [], bogus: 1}
      message = thrown(fn -> FrameSpecification.from_yaml(:t, yaml, :receive) end)
      expect(String.contains?(message, "invalid key")) |> to(eq(true))
    end

    it "throws when the total length exceeds 64 bits" do
      yaml = %{id: 1, name: "f", signals: [%{name: "big", value_start: 0, value_length: 65}]}
      message = thrown(fn -> FrameSpecification.from_yaml(:t, yaml, :receive) end)
      expect(String.contains?(message, "too long")) |> to(eq(true))
    end

    it "throws when an emitted frame's signals are not contiguous" do
      yaml = %{
        id: 1,
        name: "f",
        frequency: 100,
        signals: [%{name: "a", value_start: 8, value_length: 8}]
      }

      message = thrown(fn -> FrameSpecification.from_yaml(:t, yaml, :emit) end)
      expect(String.contains?(message, "not in the right order")) |> to(eq(true))
    end

    it "throws when an emitted frame does not fill whole bytes" do
      yaml = %{
        id: 1,
        name: "f",
        frequency: 100,
        signals: [%{name: "a", value_start: 0, value_length: 4}]
      }

      message = thrown(fn -> FrameSpecification.from_yaml(:t, yaml, :emit) end)
      expect(String.contains?(message, "fill the used bytes")) |> to(eq(true))
    end

    it "throws when an emitted frame is missing a frequency" do
      yaml = %{id: 1, name: "f", signals: [%{name: "a", value_start: 0, value_length: 8}]}
      message = thrown(fn -> FrameSpecification.from_yaml(:t, yaml, :emit) end)
      expect(String.contains?(message, "missing a 'frequency'")) |> to(eq(true))
    end

    it "accepts a well-formed emitted frame" do
      yaml = %{
        id: 1,
        name: "f",
        frequency: 100,
        signals: [%{name: "a", value_start: 0, value_length: 8}]
      }

      expect(thrown(fn -> FrameSpecification.from_yaml(:t, yaml, :emit) end)) |> to(eq(:no_throw))
    end
  end
end
