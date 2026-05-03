defmodule Cantastic.OBD2.Service.Mode09 do
  @moduledoc false
  # SAE J1979 / ISO 15031-5 Mode 0x09 — request vehicle information.
  #
  # Common PIDs:
  #   * 0x00 — supported PIDs bitmask (4 bytes)
  #   * 0x02 — VIN (Vehicle Identification Number, 17 ASCII bytes)
  #   * 0x04 — Calibration ID (N items × 16 ASCII bytes)
  #   * 0x06 — Calibration verification numbers (N items × 4 bytes)
  #   * 0x0A — ECU name (20 ASCII bytes)
  #
  # Wire format:
  #   Request:  <<0x09, pid>>
  #   Response: <<0x49, pid, num_items::8, item_1::value_length, …>>
  #
  # Unlike Mode 0x01, Mode 0x09 carries only one PID per request in practice.
  # The response always includes a `num_items` byte after the PID; for most
  # PIDs (VIN, ECU name) `num_items == 1`, but `Calibration ID` may report
  # several items when the vehicle has multiple modules.
  #
  # The decoded parameter's `:value` is *always* a list (length == num_items),
  # so callers can pattern-match it the same way regardless of PID. For
  # `kind: "ascii"` each item is a binary string; for any other kind each
  # item is a raw binary the caller can decode further.

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
        {:error, :mode_09_requires_exactly_one_parameter}
    end
  end

  @impl true
  def decode_parameters(request_specification, raw_parameters) do
    case request_specification.parameter_specifications do
      [parameter_specification] ->
        decode_single(request_specification, parameter_specification, raw_parameters)

      _ ->
        {:error, :mode_09_requires_exactly_one_parameter}
    end
  end

  defp decode_single(request_specification, parameter_specification, raw_parameters) do
    expected_id = parameter_specification.id
    item_byte_size = div(parameter_specification.value_length, 8)

    case raw_parameters do
      <<^expected_id::integer-size(8), num_items::integer-size(8), items_payload::bitstring>> ->
        case extract_items(items_payload, num_items, item_byte_size, []) do
          {:ok, items} ->
            parameter = %Parameter{
              name: parameter_specification.name,
              id: parameter_specification.id,
              request_name: request_specification.name,
              kind: parameter_specification.kind,
              value: items,
              raw_value: items_payload,
              unit: parameter_specification.unit
            }

            {:ok, %{parameter_specification.name => parameter}}

          {:error, _} = err ->
            err
        end

      <<unexpected_id::integer-size(8), _rest::bitstring>> ->
        {:error, {:pid_mismatch, expected: expected_id, got: unexpected_id}}

      _ ->
        {:error, :malformed_mode_09_response}
    end
  end

  defp extract_items(_remaining, 0, _size, acc), do: {:ok, Enum.reverse(acc)}

  defp extract_items(remaining, n, size, acc) do
    case remaining do
      <<item::binary-size(size), rest::bitstring>> ->
        extract_items(rest, n - 1, size, [item | acc])

      _ ->
        {:error, :malformed_mode_09_response}
    end
  end
end
