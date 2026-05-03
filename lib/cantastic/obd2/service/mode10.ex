defmodule Cantastic.OBD2.Service.Mode10 do
  @moduledoc false
  # ISO 14229-1 Mode 0x10 — DiagnosticSessionControl (UDS).
  #
  # Opens a non-default diagnostic session. Required before reading any DID
  # or running any routine that the ECU restricts to extended / programming
  # / safety-system access.
  #
  # Wire format:
  #   Request:  <<0x10, session_type::8>>
  #   Response: <<0x50, session_type::8, p2_server_max::16, p2_star_server_max::16>>
  #
  # `session_type` is taken from `request_specification.options.session_type`,
  # defaulting to 0x03 (extendedDiagnosticSession). Other common values:
  #   * 0x01 defaultSession
  #   * 0x02 programmingSession
  #   * 0x04 safetySystemDiagnosticSession
  #   * 0x40+ manufacturer-specific
  #
  # The response carries the ECU's timing budget for the session:
  #   * p2_server_max_ms: the longest the ECU may take to answer a request
  #     before sending a "response pending" NRC.
  #   * p2_star_server_max_ms: same after the ECU has already sent a
  #     "response pending" NRC. Reported in milliseconds (the ECU sends it
  #     in units of 10 ms).
  #
  # These are surfaced as `:integer` parameters under the keys
  # `"p2_server_max_ms"` and `"p2_star_server_max_ms"` so the caller can
  # tune its TesterPresent / request-timeout values to the ECU's session.

  @behaviour Cantastic.OBD2.Service

  alias Cantastic.OBD2.Parameter

  @default_session_type 0x03

  @impl true
  def encode_request(request_specification) do
    session_type = Map.get(request_specification.options || %{}, :session_type, @default_session_type)
    {:ok, <<request_specification.mode::big-integer-size(8), session_type::big-integer-size(8)>>}
  end

  @impl true
  def decode_parameters(request_specification, raw_parameters) do
    case raw_parameters do
      <<_session_type::big-integer-size(8),
        p2_server_max::big-integer-size(16),
        p2_star_server_max::big-integer-size(16),
        _rest::bitstring>> ->
        parameters = %{
          "p2_server_max_ms" => %Parameter{
            name: "p2_server_max_ms",
            request_name: request_specification.name,
            kind: "integer",
            value: p2_server_max,
            raw_value: <<p2_server_max::big-integer-size(16)>>,
            unit: "ms"
          },
          "p2_star_server_max_ms" => %Parameter{
            name: "p2_star_server_max_ms",
            request_name: request_specification.name,
            kind: "integer",
            value: p2_star_server_max * 10,
            raw_value: <<p2_star_server_max::big-integer-size(16)>>,
            unit: "ms"
          }
        }

        {:ok, parameters}

      _ ->
        {:error, :malformed_session_control_response}
    end
  end
end
