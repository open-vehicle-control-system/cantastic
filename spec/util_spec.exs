defmodule Cantastic.UtilSpec do
  use ESpec
  alias Cantastic.Util

  describe ".hex_to_bin/1" do
    it "returns nil when given nil" do
      expect(Util.hex_to_bin(nil)) |> to(be_nil())
    end

    it "decodes a single hex digit by left-padding with zero" do
      expect(Util.hex_to_bin("A")) |> to(eq(<<0x0A>>))
    end

    it "decodes two-digit hex" do
      expect(Util.hex_to_bin("AB")) |> to(eq(<<0xAB>>))
    end

    it "decodes a longer hex string" do
      expect(Util.hex_to_bin("DEADBEEF")) |> to(eq(<<0xDE, 0xAD, 0xBE, 0xEF>>))
    end
  end

  describe ".bin_to_hex/1" do
    it "encodes a single byte" do
      expect(Util.bin_to_hex(<<0xAB>>)) |> to(eq("AB"))
    end

    it "encodes multiple bytes uppercased" do
      expect(Util.bin_to_hex(<<0xDE, 0xAD, 0xBE, 0xEF>>)) |> to(eq("DEADBEEF"))
    end

    it "round-trips with hex_to_bin" do
      expect(Util.bin_to_hex(Util.hex_to_bin("CAFEBABE"))) |> to(eq("CAFEBABE"))
    end
  end

  describe ".integer_to_hex/1" do
    it "left-pads to two characters for small values" do
      expect(Util.integer_to_hex(0)) |> to(eq("00"))
      expect(Util.integer_to_hex(1)) |> to(eq("01"))
      expect(Util.integer_to_hex(0x0F)) |> to(eq("0F"))
    end

    it "uses uppercase hex" do
      expect(Util.integer_to_hex(0xAB)) |> to(eq("AB"))
    end

    it "does not truncate values larger than one byte" do
      expect(Util.integer_to_hex(0x100)) |> to(eq("100"))
      expect(Util.integer_to_hex(0x7DF)) |> to(eq("7DF"))
    end
  end

  describe ".string_to_integer/1" do
    it "parses a plain decimal string" do
      expect(Util.string_to_integer("42")) |> to(eq(42))
    end

    it "parses a single digit by left-padding" do
      expect(Util.string_to_integer("7")) |> to(eq(7))
    end
  end

  describe ".integer_to_bin_big/2" do
    it "returns nil for nil input" do
      expect(Util.integer_to_bin_big(nil)) |> to(be_nil())
      expect(Util.integer_to_bin_big(nil, 8)) |> to(be_nil())
    end

    it "encodes big-endian with default 16-bit size" do
      expect(Util.integer_to_bin_big(0x1234)) |> to(eq(<<0x12, 0x34>>))
    end

    it "respects an explicit size argument" do
      expect(Util.integer_to_bin_big(0xAB, 8)) |> to(eq(<<0xAB>>))
      expect(Util.integer_to_bin_big(0x12345678, 32)) |> to(eq(<<0x12, 0x34, 0x56, 0x78>>))
    end
  end

  describe ".integer_to_bin_little/2" do
    it "returns nil for nil input" do
      expect(Util.integer_to_bin_little(nil)) |> to(be_nil())
    end

    it "encodes little-endian with default 16-bit size" do
      expect(Util.integer_to_bin_little(0x1234)) |> to(eq(<<0x34, 0x12>>))
    end

    it "respects an explicit size argument" do
      expect(Util.integer_to_bin_little(0x12345678, 32)) |> to(eq(<<0x78, 0x56, 0x34, 0x12>>))
    end
  end
end
