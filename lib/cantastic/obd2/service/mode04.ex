defmodule Cantastic.OBD2.Service.Mode04 do
  @moduledoc false
  # SAE J1979 / ISO 15031-5 Mode 0x04 — clear emission-related DTCs and
  # diagnostic information.
  #
  # Request:  <<0x04>>
  # Response: <<0x44>>  (positive acknowledgement, no payload)
  #
  # If the ECU refuses (typical reasons: engine running, security access
  # required, conditions not correct) it returns a negative response which is
  # surfaced to subscribers as `{:handle_obd2_error, {:nrc, …}}` by
  # `Cantastic.OBD2.Response.interpret/2`.

  @behaviour Cantastic.OBD2.Service

  @impl true
  def encode_request(request_specification) do
    {:ok, <<request_specification.mode::big-integer-size(8)>>}
  end

  @impl true
  def decode_parameters(_request_specification, _raw_parameters) do
    {:ok, %{}}
  end
end
