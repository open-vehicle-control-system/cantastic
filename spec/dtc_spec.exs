defmodule Cantastic.DTCSpec do
  use ESpec
  alias Cantastic.DTC

  describe "decoding a 16-bit raw DTC" do
    context "when the top 2 bits are 00" do
      it "produces a P-prefixed (powertrain) string" do
        expect(DTC.decode(<<0x03, 0x01>>)) |> to(eq({:ok, "P0301"}))
        expect(DTC.decode(<<0x04, 0x20>>)) |> to(eq({:ok, "P0420"}))
        expect(DTC.decode(<<0x00, 0x00>>)) |> to(eq({:ok, "P0000"}))
      end
    end

    context "when the top 2 bits are 01" do
      it "produces a C-prefixed (chassis) string" do
        expect(DTC.decode(<<0x40, 0x42>>)) |> to(eq({:ok, "C0042"}))
        expect(DTC.decode(<<0x71, 0x23>>)) |> to(eq({:ok, "C3123"}))
      end
    end

    context "when the top 2 bits are 10" do
      it "produces a B-prefixed (body) string" do
        expect(DTC.decode(<<0x80, 0x01>>)) |> to(eq({:ok, "B0001"}))
        expect(DTC.decode(<<0x8F, 0xFF>>)) |> to(eq({:ok, "B0FFF"}))
      end
    end

    context "when the top 2 bits are 11" do
      it "produces a U-prefixed (network) string" do
        expect(DTC.decode(<<0xC1, 0x00>>)) |> to(eq({:ok, "U0100"}))
        expect(DTC.decode(<<0xFF, 0xFF>>)) |> to(eq({:ok, "U3FFF"}))
      end
    end

    context "when given fewer than 16 bits" do
      it "returns :invalid_dtc" do
        expect(DTC.decode(<<0x12>>)) |> to(eq({:error, :invalid_dtc}))
        expect(DTC.decode(<<>>)) |> to(eq({:error, :invalid_dtc}))
      end
    end
  end

  describe "encoding a 5-char DTC string" do
    context "for each system letter" do
      it "packs system + first digit + 12-bit remainder into 16 bits" do
        expect(DTC.encode("P0301")) |> to(eq({:ok, <<0x03, 0x01>>}))
        expect(DTC.encode("C0042")) |> to(eq({:ok, <<0x40, 0x42>>}))
        expect(DTC.encode("B0001")) |> to(eq({:ok, <<0x80, 0x01>>}))
        expect(DTC.encode("U0100")) |> to(eq({:ok, <<0xC1, 0x00>>}))
      end
    end

    context "at the maximum value for each system" do
      it "uses all 14 code bits" do
        expect(DTC.encode("P3FFF")) |> to(eq({:ok, <<0x3F, 0xFF>>}))
        expect(DTC.encode("U3FFF")) |> to(eq({:ok, <<0xFF, 0xFF>>}))
      end
    end

    context "with an unknown system letter" do
      it "returns :invalid_dtc_system_letter" do
        expect(DTC.encode("X0301")) |> to(eq({:error, :invalid_dtc_system_letter}))
      end
    end

    context "with non-hex characters in the code" do
      it "returns :invalid_dtc_hex" do
        expect(DTC.encode("P0ZZZ")) |> to(eq({:error, :invalid_dtc_hex}))
      end
    end

    context "with the wrong length" do
      it "returns :invalid_dtc_format" do
        expect(DTC.encode("P030")) |> to(eq({:error, :invalid_dtc_format}))
        expect(DTC.encode("P03012")) |> to(eq({:error, :invalid_dtc_format}))
      end
    end
  end

  describe "round-tripping" do
    it "encodes what decode produces" do
      for code <- ["P0301", "P0420", "C1234", "B0FFF", "U0100", "U3FFF"] do
        {:ok, raw} = DTC.encode(code)
        expect(DTC.decode(raw)) |> to(eq({:ok, code}))
      end
    end
  end

  describe "decoding a list of raw DTCs" do
    context "when the payload is empty" do
      it "returns an empty list" do
        expect(DTC.decode_list(<<>>)) |> to(eq({:ok, []}))
      end
    end

    context "when the payload contains one DTC" do
      it "returns a single-element list" do
        expect(DTC.decode_list(<<0x03, 0x01>>)) |> to(eq({:ok, ["P0301"]}))
      end
    end

    context "when the payload contains several DTCs from different systems" do
      it "decodes them in order" do
        expect(DTC.decode_list(<<0x03, 0x01, 0x40, 0x42, 0xC1, 0x00>>))
        |> to(eq({:ok, ["P0301", "C0042", "U0100"]}))
      end
    end

    context "when the payload is not a multiple of 2 bytes" do
      it "returns :malformed_dtc_list" do
        expect(DTC.decode_list(<<0x03>>)) |> to(eq({:error, :malformed_dtc_list}))
        expect(DTC.decode_list(<<0x03, 0x01, 0xC1>>)) |> to(eq({:error, :malformed_dtc_list}))
      end
    end
  end
end
