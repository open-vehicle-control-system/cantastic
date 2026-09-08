defmodule Cantastic.FrameInterpretSpec do
  use ESpec
  alias Cantastic.{Frame, TestFactory}

  # One signal reading a 16-bit value at bit offset 16 — so the frame
  # needs at least 4 data bytes.
  let :spec,
    do:
      TestFactory.frame_specification(%{
        name: "needs_four_bytes",
        signal_specifications: [
          TestFactory.integer_signal_specification(%{
            name: "value",
            value_start: 16,
            value_length: 16,
            endianness: "little",
            sign: "unsigned"
          })
        ]
      })

  defp frame(raw_data),
    do: %Frame{id: 0x123, raw_data: raw_data, byte_number: byte_size(raw_data), network_name: :test}

  describe ".interpret/2" do
    it "decodes a frame long enough for its signals" do
      {:ok, decoded} = Frame.interpret(frame(<<0, 0, 210, 4>>), spec())
      expect(decoded.signals["value"].value) |> to(eq(1234))
    end

    it "returns an error rather than raising on a frame too short for its signals" do
      # A single zero byte where four are expected — the boot-time bus
      # frame that used to crash the whole receiver.
      {:error, _reason} = Frame.interpret(frame(<<0>>), spec())
    end
  end
end
