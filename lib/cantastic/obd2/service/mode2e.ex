defmodule Cantastic.OBD2.Service.Mode2E do
  @moduledoc false
  # ISO 14229-1 Mode 0x2E — WriteDataByIdentifier (UDS).
  #
  # Pair to Mode 0x22: same 16-bit DIDs, write side. Most ECUs require an
  # extended diagnostic session (Mode 0x10 sub-function 0x03) and security
  # access (Mode 0x27) before a Mode 0x2E write is accepted.
  #
  # Wire format:
  #   Request:  <<0x2E, did::16, data::value_length>>
  #   Response: <<0x6E, did::16>>  (positive ack, no payload)
  #
  # The DID comes from the single parameter's `id`; the bytes to write come
  # from `request_specification.options.data` as a raw binary. The
  # parameter's `value_length` is informational on the request side — the
  # bytes from `options.data` are sent verbatim — but is required so the
  # response decoder can verify the DID echo.
  #
  # On a positive response cantastic delivers
  # `{:handle_obd2_response, %Response{mode: 0x6E, parameters: %{}}}`,
  # signalling that the ECU accepted the write. Refusals (security access
  # denied, conditions not correct, …) come through as
  # `{:handle_obd2_error, {:nrc, _, _, _}}` like any other UDS service.

  @behaviour Cantastic.OBD2.Service

  @impl true
  def encode_request(request_specification) do
    case request_specification.parameter_specifications do
      [parameter_specification] ->
        data = Map.get(request_specification.options || %{}, :data, <<>>)

        {:ok,
         <<request_specification.mode::big-integer-size(8),
           parameter_specification.id::big-integer-size(16),
           data::bitstring>>}

      _ ->
        {:error, :mode_2e_requires_exactly_one_parameter}
    end
  end

  @impl true
  def decode_parameters(request_specification, raw_parameters) do
    case request_specification.parameter_specifications do
      [parameter_specification] ->
        expected_did = parameter_specification.id

        case raw_parameters do
          <<^expected_did::big-integer-size(16), _rest::bitstring>> ->
            {:ok, %{}}

          <<got_did::big-integer-size(16), _rest::bitstring>> ->
            {:error, {:did_mismatch, expected: expected_did, got: got_did}}

          _ ->
            {:error, :malformed_mode_2e_response}
        end

      _ ->
        {:error, :mode_2e_requires_exactly_one_parameter}
    end
  end
end
