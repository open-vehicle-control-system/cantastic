defmodule Cantastic.FrameSpecificationSpec do
  use ESpec
  alias Cantastic.FrameSpecification

  describe ".from_yaml/3 for received frames" do
    let :network_name, do: :test_network
    let :result, do: FrameSpecification.from_yaml(network_name(), yaml(), :receive)

    context "with the minimum required keys" do
      let :yaml, do: %{
        id: 0x100,
        name: "battery_status",
        signals: [
          %{name: "voltage", value_start: 0, value_length: 16}
        ]
      }

      it "returns a populated frame specification with sensible defaults" do
        {:ok, spec} = result()
        expect(spec.id) |> to(eq(0x100))
        expect(spec.name) |> to(eq("battery_status"))
        expect(spec.network_name) |> to(eq(:test_network))
        expect(spec.allowed_frequency_leeway) |> to(eq(10))
        expect(spec.allowed_missing_frames) |> to(eq(5))
        expect(spec.allowed_missing_frames_period) |> to(eq(5_000))
        expect(spec.required_on_time_frames) |> to(eq(5))
        expect(spec.checksum_required) |> to(be_false())
        expect(spec.checksum_signal_specification) |> to(be_nil())
        expect(length(spec.signal_specifications)) |> to(eq(1))
        expect(spec.data_length) |> to(eq(16))
        expect(spec.byte_number) |> to(eq(2))
      end
    end

    context "with a checksum signal" do
      let :yaml, do: %{
        id: 0x100,
        name: "battery_status",
        signals: [
          %{name: "voltage", value_start: 0, value_length: 8},
          %{name: "checksum", kind: "checksum", value_start: 8, value_length: 8}
        ]
      }

      it "marks the frame as requiring a checksum and stores the checksum spec" do
        {:ok, spec} = result()
        expect(spec.checksum_required) |> to(be_true())
        expect(spec.checksum_signal_specification.name) |> to(eq("checksum"))
      end
    end

    context "with two checksum signals" do
      let :yaml, do: %{
        id: 0x100,
        name: "bad_frame",
        signals: [
          %{name: "checksum_a", kind: "checksum", value_start: 0, value_length: 8},
          %{name: "checksum_b", kind: "checksum", value_start: 8, value_length: 8}
        ]
      }

      it "throws a configuration error" do
        expect(fn -> result() end) |> to(throw_term())
      end
    end

    context "with a frame longer than 64 bits" do
      let :yaml, do: %{
        id: 0x100,
        name: "too_long",
        signals: [
          %{name: "a", value_start: 0, value_length: 64},
          %{name: "b", value_start: 64, value_length: 8}
        ]
      }

      it "throws a configuration error" do
        expect(fn -> result() end) |> to(throw_term())
      end
    end

    context "with an unknown YAML key on the frame" do
      let :yaml, do: %{id: 0x100, name: "frame", foo: "bar", signals: []}

      it "throws a configuration error" do
        expect(fn -> result() end) |> to(throw_term())
      end
    end
  end

  describe ".from_yaml/3 for emitted frames" do
    let :network_name, do: :test_network
    let :result, do: FrameSpecification.from_yaml(network_name(), yaml(), :emit)

    context "with contiguous signals filling the bytes" do
      let :yaml, do: %{
        id: 0x200,
        name: "drive_request",
        frequency: 100,
        signals: [
          %{name: "throttle", value_start: 0, value_length: 8},
          %{name: "brake", value_start: 8, value_length: 8}
        ]
      }

      it "is accepted" do
        {:ok, spec} = result()
        expect(spec.frequency) |> to(eq(100))
        expect(spec.byte_number) |> to(eq(2))
      end
    end

    context "with non-contiguous signals" do
      let :yaml, do: %{
        id: 0x200,
        name: "drive_request",
        frequency: 100,
        signals: [
          %{name: "throttle", value_start: 0, value_length: 8},
          %{name: "brake", value_start: 16, value_length: 8}
        ]
      }

      it "throws a configuration error" do
        expect(fn -> result() end) |> to(throw_term())
      end
    end

    context "with bits that don't fill whole bytes" do
      let :yaml, do: %{
        id: 0x200,
        name: "drive_request",
        frequency: 100,
        signals: [
          %{name: "flag", value_start: 0, value_length: 1}
        ]
      }

      it "throws a configuration error" do
        expect(fn -> result() end) |> to(throw_term())
      end
    end

    context "without a frequency" do
      let :yaml, do: %{
        id: 0x200,
        name: "drive_request",
        signals: [
          %{name: "throttle", value_start: 0, value_length: 8}
        ]
      }

      it "throws a configuration error during validation" do
        expect(fn -> result() end) |> to(throw_term())
      end
    end
  end

  describe ".validate_specification!/2" do
    import Cantastic.TestFactory, only: [frame_specification: 1]

    it "passes for a valid received frame spec" do
      spec = frame_specification(%{frequency: 100})
      expect(fn -> FrameSpecification.validate_specification!(spec, :receive) end) |> to_not(throw_term())
    end

    it "throws when name is missing" do
      spec = frame_specification(%{name: nil})
      expect(fn -> FrameSpecification.validate_specification!(spec, :receive) end) |> to(throw_term())
    end

    it "throws when id is missing" do
      spec = frame_specification(%{id: nil})
      expect(fn -> FrameSpecification.validate_specification!(spec, :receive) end) |> to(throw_term())
    end

    it "throws when an emitted frame has no frequency" do
      spec = frame_specification(%{frequency: nil})
      expect(fn -> FrameSpecification.validate_specification!(spec, :emit) end) |> to(throw_term())
    end
  end
end
