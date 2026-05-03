defmodule Cantastic.FrameSpec do
  use ESpec
  alias Cantastic.{Frame, FrameSpecification, SignalSpecification}
  alias Decimal, as: D

  defp signal_spec(overrides) do
    base = %SignalSpecification{
      name: "signal",
      network_name: :test_network,
      frame_id: 0x100,
      frame_name: "test_frame",
      kind: "integer",
      precision: 2,
      sign: "unsigned",
      endianness: "little",
      value_start: 0,
      value_length: 8,
      scale: D.new(1),
      offset: D.new(0)
    }
    Map.merge(base, Map.new(overrides))
  end

  describe ".build_raw/2" do
    let :spec, do: %FrameSpecification{
      id: 0x100,
      name: "drive_request",
      network_name: :test_network,
      frequency: 100,
      signal_specifications: [
        signal_spec(%{name: "throttle", value_start: 0, value_length: 8}),
        signal_spec(%{name: "brake", value_start: 8, value_length: 8})
      ],
      data_length: 16,
      byte_number: 2,
      checksum_required: false
    }

    it "concatenates the encoded signals and pads to a SocketCAN frame" do
      {:ok, raw} = Frame.build_raw(spec(), %{"throttle" => 0x12, "brake" => 0x34})
      <<id::little-integer-size(16), _zeros::16, byte_number::8, _zeros2::24, data::binary-size(8)>> = raw
      expect(id) |> to(eq(0x100))
      expect(byte_number) |> to(eq(2))
      expect(data) |> to(eq(<<0x12, 0x34, 0, 0, 0, 0, 0, 0>>))
    end

    it "fails loud when a signal value is missing from the parameters" do
      expect(fn -> Frame.build_raw(spec(), %{"throttle" => 0x12}) end) |> to(raise_exception())
    end
  end

  describe ".interpret/2" do
    let :spec, do: %FrameSpecification{
      id: 0x100,
      name: "battery_status",
      network_name: :test_network,
      signal_specifications: [
        signal_spec(%{name: "voltage", value_start: 0, value_length: 8}),
        signal_spec(%{name: "current", value_start: 8, value_length: 8, sign: "signed"})
      ],
      checksum_required: false
    }

    it "decodes each signal and exposes them by name" do
      frame = %Frame{id: 0x100, raw_data: <<0x32, 0xFF>>, byte_number: 2, network_name: :test_network}
      {:ok, decoded} = Frame.interpret(frame, spec())
      expect(decoded.name) |> to(eq("battery_status"))
      expect(decoded.signals["voltage"].value) |> to(eq(50))
      expect(decoded.signals["current"].value) |> to(eq(-1))
    end
  end

  describe ".to_raw/1" do
    it "produces a 16-byte SocketCAN frame with little-endian id and zero padding" do
      frame = %Frame{id: 0x7E8, raw_data: <<0x41, 0x0D, 0x32>>, byte_number: 3, network_name: :test_network}
      raw = Frame.to_raw(frame)
      expect(byte_size(raw)) |> to(eq(16))
      <<id::little-integer-size(16), 0, 0, byte_number::8, 0, 0, 0, payload::binary-size(8)>> = raw
      expect(id) |> to(eq(0x7E8))
      expect(byte_number) |> to(eq(3))
      expect(payload) |> to(eq(<<0x41, 0x0D, 0x32, 0, 0, 0, 0, 0>>))
    end
  end

  describe ".to_string/1" do
    it "renders the network, id, byte count and hex bytes" do
      frame = %Frame{
        id: 0x7A1,
        raw_data: <<0x00, 0xAA, 0xBB>>,
        byte_number: 3,
        network_name: :my_network
      }
      expect(Frame.to_string(frame)) |> to(eq("[Frame] my_network - 7A1  [3]  00 AA BB"))
    end
  end

  describe ".format_id/1" do
    it "uppercases the hex id with at least two characters" do
      expect(Frame.format_id(%Frame{id: 0x100})) |> to(eq("100"))
      expect(Frame.format_id(%Frame{id: 0x0F})) |> to(eq("0F"))
    end
  end

  describe ".format_data/1" do
    it "renders raw_data as space-separated hex pairs" do
      frame = %Frame{raw_data: <<0xDE, 0xAD, 0xBE, 0xEF>>}
      expect(Frame.format_data(frame)) |> to(eq("DE AD BE EF"))
    end
  end
end
