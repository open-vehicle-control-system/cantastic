defmodule Cantastic.OBD2.Service.Mode1A do
  @moduledoc false
  # ISO 14230-3 (KWP2000) Mode 0x1A — ReadECUIdentification.
  #
  # Single-byte identification option, ASCII payload. Used by Toyota and
  # several other manufacturers as their VIN / ECU info read in place of
  # OBD2 Mode 0x09.
  #
  # Wire format:
  #   Request:  <<0x1A, identification_option::8>>
  #   Response: <<0x5A, identification_option::8, data::value_length>>
  #
  # Common identification options:
  #   * 0x80 default ECU identification
  #   * 0x81 ECU identifier
  #   * 0x86 VIN
  #   * 0x87 calibration ID
  #   * 0x88 calibration verification number
  #
  # The user declares one parameter — `id` is the identification option,
  # `value_length` is the expected payload size in bits, `kind` is usually
  # `"ascii"` (or `"bytes"` for binary identifiers like 0x88).

  @behaviour Cantastic.OBD2.Service

  alias Cantastic.OBD2.Parameter

  @impl true
  def encode_request(request_specification) do
    case request_specification.parameter_specifications do
      [parameter_specification] ->
        {:ok,
         <<request_specification.mode::big-integer-size(8),
           parameter_specification.id::big-integer-size(8)>>}

      _ ->
        {:error, :mode_1a_requires_exactly_one_parameter}
    end
  end

  @impl true
  def decode_parameters(request_specification, raw_parameters) do
    case request_specification.parameter_specifications do
      [parameter_specification] ->
        decode_single(request_specification, parameter_specification, raw_parameters)

      _ ->
        {:error, :mode_1a_requires_exactly_one_parameter}
    end
  end

  defp decode_single(request_specification, parameter_specification, raw_parameters) do
    expected_id = parameter_specification.id
    value_length = parameter_specification.value_length

    case raw_parameters do
      <<^expected_id::integer-size(8), data::bitstring-size(value_length), _rest::bitstring>> ->
        parameter = %Parameter{
          name: parameter_specification.name,
          id: parameter_specification.id,
          request_name: request_specification.name,
          kind: parameter_specification.kind,
          value: data,
          raw_value: data,
          unit: parameter_specification.unit
        }

        {:ok, %{parameter_specification.name => parameter}}

      <<got_id::integer-size(8), _rest::bitstring>> ->
        {:error, {:identification_option_mismatch, expected: expected_id, got: got_id}}

      _ ->
        {:error, :malformed_mode_1a_response}
    end
  end
end
