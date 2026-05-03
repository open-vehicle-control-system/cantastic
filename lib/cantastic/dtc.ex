defmodule Cantastic.DTC do
  @moduledoc """
  Encode and decode SAE J2012 / ISO 15031-6 Diagnostic Trouble Codes.

  A DTC is 16 bits on the wire and 5 characters as a string: one system letter
  (`P`, `C`, `B`, `U`) followed by 4 hexadecimal digits.

  The top 2 bits of the raw value encode the system (`00` = P/powertrain,
  `01` = C/chassis, `10` = B/body, `11` = U/network). The next 2 bits hold the
  first hex digit (always 0–3), and the last 12 bits hold the remaining three
  hex digits.

  ## Examples

      iex> Cantastic.DTC.decode(<<0x03, 0x01>>)
      {:ok, "P0301"}

      iex> Cantastic.DTC.decode(<<0xC1, 0x00>>)
      {:ok, "U0100"}

      iex> Cantastic.DTC.encode("P0301")
      {:ok, <<0x03, 0x01>>}

      iex> Cantastic.DTC.encode("U0100")
      {:ok, <<0xC1, 0x00>>}
  """

  @system_to_letter %{0 => "P", 1 => "C", 2 => "B", 3 => "U"}
  @letter_to_system %{"P" => 0, "C" => 1, "B" => 2, "U" => 3}

  @doc """
  Decode a 16-bit raw DTC into its 5-character string form.

  Returns `{:ok, code}` or `{:error, reason}`.

  ## Examples

      iex> Cantastic.DTC.decode(<<0x04, 0x20>>)
      {:ok, "P0420"}

      iex> Cantastic.DTC.decode(<<0xFF, 0xFF>>)
      {:ok, "U3FFF"}

      iex> Cantastic.DTC.decode(<<0x12>>)
      {:error, :invalid_dtc}
  """
  def decode(<<system::2, first_digit::2, rest::12>>) do
    letter = Map.fetch!(@system_to_letter, system)
    hex =
      (first_digit * 0x1000 + rest)
      |> Integer.to_string(16)
      |> String.pad_leading(4, "0")
      |> String.upcase()

    {:ok, letter <> hex}
  end

  def decode(_), do: {:error, :invalid_dtc}

  @doc """
  Encode a 5-character DTC string back to its 16-bit raw form.

  Returns `{:ok, binary}` or `{:error, reason}`.

  ## Examples

      iex> Cantastic.DTC.encode("C0042")
      {:ok, <<0x40, 0x42>>}

      iex> Cantastic.DTC.encode("X0000")
      {:error, :invalid_dtc_system_letter}

      iex> Cantastic.DTC.encode("P0ZZZ")
      {:error, :invalid_dtc_hex}
  """
  def encode(<<letter::binary-size(1), hex::binary-size(4)>>) do
    case Map.fetch(@letter_to_system, letter) do
      {:ok, system} ->
        case Integer.parse(hex, 16) do
          {value, ""} when value <= 0x3FFF ->
            first_digit = div(value, 0x1000)
            rest = rem(value, 0x1000)
            {:ok, <<system::2, first_digit::2, rest::12>>}

          _ ->
            {:error, :invalid_dtc_hex}
        end

      :error ->
        {:error, :invalid_dtc_system_letter}
    end
  end

  def encode(_), do: {:error, :invalid_dtc_format}

  @doc """
  Decode a sequence of 16-bit raw DTCs into a list of code strings.

  This is the payload shape used by Mode 0x03, 0x07 and 0x0A responses,
  after the leading SID and count bytes have been stripped.

  Returns `{:ok, codes}` or `{:error, reason}`.

  ## Examples

      iex> Cantastic.DTC.decode_list(<<>>)
      {:ok, []}

      iex> Cantastic.DTC.decode_list(<<0x03, 0x01, 0xC1, 0x00>>)
      {:ok, ["P0301", "U0100"]}

      iex> Cantastic.DTC.decode_list(<<0x03>>)
      {:error, :malformed_dtc_list}
  """
  def decode_list(<<>>), do: {:ok, []}

  def decode_list(<<raw::binary-size(2), rest::bitstring>>) do
    with {:ok, code} <- decode(raw),
         {:ok, more} <- decode_list(rest) do
      {:ok, [code | more]}
    end
  end

  def decode_list(_), do: {:error, :malformed_dtc_list}

  @doc """
  Decode a 24-bit UDS DTC into its code string and fault-type byte.

  ISO 14229-1 DTCs carry one extra byte beyond the OBD2 16-bit form. The
  first two bytes encode the same `P0301`-style code; the third byte is a
  "fault type" extension whose meaning varies by manufacturer (powertrain
  vs. body, electrical vs. functional, etc.). `decode_uds/1` returns both
  parts so a caller can decide what to do with the extension.

  Returns `{:ok, %{code: code, fault_type: fault_type}}` or
  `{:error, reason}`.

  ## Examples

      iex> Cantastic.DTC.decode_uds(<<0x03, 0x01, 0x00>>)
      {:ok, %{code: "P0301", fault_type: 0x00}}

      iex> Cantastic.DTC.decode_uds(<<0xC1, 0x00, 0x88>>)
      {:ok, %{code: "U0100", fault_type: 0x88}}

      iex> Cantastic.DTC.decode_uds(<<0x12, 0x34>>)
      {:error, :invalid_uds_dtc}
  """
  def decode_uds(<<system::2, first_digit::2, rest::12, fault_type::8>>) do
    letter = Map.fetch!(@system_to_letter, system)

    hex =
      (first_digit * 0x1000 + rest)
      |> Integer.to_string(16)
      |> String.pad_leading(4, "0")
      |> String.upcase()

    {:ok, %{code: letter <> hex, fault_type: fault_type}}
  end

  def decode_uds(_), do: {:error, :invalid_uds_dtc}
end
