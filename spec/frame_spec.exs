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
  end
end
