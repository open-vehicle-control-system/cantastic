defmodule Cantastic.FrameSpec do
  use ESpec
  alias Cantastic.Frame

  describe "rendering a frame for debugging" do
    context "with raw data and a network name" do
      let :frame, do: %Frame{
        id: 0x7A1,
        raw_data: <<0x00, 0xAA, 0xBB>>,
        byte_number: 3,
        network_name: :my_network
      }

      it "produces a one-line representation including network, id, byte count, and hex bytes" do
        expect(Frame.to_string(frame())) |> to(eq("[Frame] my_network - 7A1  [3]  00 AA BB"))
      end
    end

    context "with an extended identifier" do
      let :frame, do: %Frame{
        id: 0x00000903,
        extended: true,
        raw_data: <<0x00, 0x00, 0x27, 0x10>>,
        byte_number: 4,
        network_name: :my_network
      }

      it "shows the id on eight hex digits and marks it extended" do
        expect(Frame.to_string(frame())) |> to(eq("[Frame] my_network - 00000903 (ext)  [4]  00 00 27 10"))
      end
    end
  end

  describe "encoding a frame for the socket" do
    # struct can_frame: little-endian 32-bit can_id, DLC, 3 padding bytes,
    # 8 data bytes. CAN_EFF_FLAG (0x80000000) marks a 29-bit identifier.
    it "writes a standard id in the low 11 bits with no flag" do
      frame = %Frame{id: 0x7A1, raw_data: <<0xAA, 0xBB>>, byte_number: 2}

      expect(Frame.to_raw(frame))
      |> to(eq(<<0xA1, 0x07, 0x00, 0x00, 2, 0, 0, 0, 0xAA, 0xBB, 0, 0, 0, 0, 0, 0>>))
    end

    it "sets CAN_EFF_FLAG for an extended id, even one that would fit in 11 bits" do
      # A VESC SET_DUTY frame for controller 3 has id 0x000003 and is
      # extended: without the flag the bus would carry standard id 0x003.
      frame = %Frame{id: 0x000003, extended: true, raw_data: <<0, 0, 0, 0>>, byte_number: 4}

      expect(Frame.to_raw(frame))
      |> to(eq(<<0x03, 0x00, 0x00, 0x80, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>))
    end

    it "carries a full 29-bit id" do
      frame = %Frame{id: 0x1FFFFFFF, extended: true, raw_data: <<>>, byte_number: 0}

      expect(Frame.to_raw(frame))
      |> to(eq(<<0xFF, 0xFF, 0xFF, 0x9F, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0>>))
    end
  end
end
