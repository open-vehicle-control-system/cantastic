defmodule Cantastic.UtilSpec do
  use ESpec
  alias Cantastic.Util

  describe ".hex_to_bin/1" do
    it "decodes an even-length hex string into binary" do
      expect(Util.hex_to_bin("FF")) |> to(eq(<<255>>))
    end

    it "left-pads a single nibble before decoding" do
      expect(Util.hex_to_bin("F")) |> to(eq(<<15>>))
    end

    it "returns nil for nil input" do
      expect(Util.hex_to_bin(nil)) |> to(eq(nil))
    end
  end

  describe ".bin_to_hex/1" do
    it "encodes binary as an uppercase hex string" do
      expect(Util.bin_to_hex(<<0xAB, 0xCD>>)) |> to(eq("ABCD"))
    end
  end

  describe ".integer_to_hex/1" do
    it "renders an integer as a zero-padded hex string" do
      expect(Util.integer_to_hex(255)) |> to(eq("FF"))
      expect(Util.integer_to_hex(5)) |> to(eq("05"))
    end
  end

  describe ".string_to_integer/1" do
    it "parses a plain integer string" do
      expect(Util.string_to_integer("42")) |> to(eq(42))
    end

    it "left-pads a single character before parsing" do
      expect(Util.string_to_integer("7")) |> to(eq(7))
    end

    it "returns an :error tuple for a non-integer string" do
      expect(Util.string_to_integer("xx")) |> to(eq({:error, "'xx' is not a valid integer"}))
    end
  end

  describe ".integer_to_bin_big/2" do
    it "defaults to a 16-bit big-endian binary" do
      expect(Util.integer_to_bin_big(1)) |> to(eq(<<0, 1>>))
    end

    it "honours an explicit size" do
      expect(Util.integer_to_bin_big(1, 8)) |> to(eq(<<1>>))
    end

    it "returns nil for nil input" do
      expect(Util.integer_to_bin_big(nil)) |> to(eq(nil))
    end
  end

  describe ".integer_to_bin_little/2" do
    it "produces a little-endian binary" do
      expect(Util.integer_to_bin_little(1, 16)) |> to(eq(<<1, 0>>))
    end

    it "returns nil for nil input" do
      expect(Util.integer_to_bin_little(nil)) |> to(eq(nil))
    end
  end
end
