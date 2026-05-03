defmodule Cantastic.OBD2.Service.Mode19 do
  @moduledoc false
  # ISO 14229-1 Mode 0x19 — ReadDTCInformation (UDS).
  #
  # Modern equivalent of OBD2 Mode 0x03. Returns DTCs *with status bytes*,
  # which tell you whether each fault is confirmed / pending / test-failed-
  # since-last-clear / etc. Many post-2010 ECUs only respond to 0x19, not
  # 0x03.
  #
  # Mode 0x19 has many sub-functions; this service implements the most
  # common one — `0x02 reportDTCByStatusMask`. Other sub-functions
  # (`0x01 reportNumberOfDTCByStatusMask`, `0x06 reportDTCExtDataRecord`,
  # `0x0A reportSupportedDTC`, …) can be added without changing the YAML
  # this service already accepts.
  #
  # Wire format (sub-function 0x02):
  #   Request:  <<0x19, 0x02, status_mask::8>>
  #   Response: <<0x59, 0x02, dtc_status_availability_mask::8,
  #               dtc::24, status::8, dtc::24, status::8, …>>
  #
  # Options:
  #   * `sub_function` — defaults to `0x02`
  #   * `status_mask`  — defaults to `0xFF` (match all status bits)
  #
  # The response is surfaced as a single parameter, `"dtc_records"`, whose
  # `:value` is a list of maps like
  # `%{code: "P0301", fault_type: 0x00, status: 0x09}`. The status byte is
  # bit-packed per ISO 14229-1 Annex D.

  @behaviour Cantastic.OBD2.Service

  alias Cantastic.{DTC, OBD2.Parameter}

  @default_sub_function 0x02
  @default_status_mask 0xFF

  @impl true
  def encode_request(request_specification) do
    sub_function = Map.get(request_specification.options || %{}, :sub_function, @default_sub_function)
    status_mask = Map.get(request_specification.options || %{}, :status_mask, @default_status_mask)

    {:ok,
     <<request_specification.mode::big-integer-size(8),
       sub_function::big-integer-size(8),
       status_mask::big-integer-size(8)>>}
  end

  @impl true
  def decode_parameters(request_specification, raw_parameters) do
    case raw_parameters do
      <<_sub_function::big-integer-size(8),
        _availability_mask::big-integer-size(8),
        records::bitstring>> ->
        with {:ok, decoded} <- decode_records(records, []) do
          parameter = %Parameter{
            name: "dtc_records",
            request_name: request_specification.name,
            kind: "dtc_record_list",
            value: decoded,
            raw_value: records
          }

          {:ok, %{"dtc_records" => parameter}}
        end

      _ ->
        {:error, :malformed_mode_19_response}
    end
  end

  defp decode_records(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp decode_records(<<dtc::binary-size(3), status::big-integer-size(8), rest::bitstring>>, acc) do
    case DTC.decode_uds(dtc) do
      {:ok, %{code: code, fault_type: fault_type}} ->
        decode_records(rest, [%{code: code, fault_type: fault_type, status: status} | acc])

      {:error, _} = err ->
        err
    end
  end

  defp decode_records(_, _acc), do: {:error, :malformed_mode_19_response}
end
