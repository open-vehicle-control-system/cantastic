defmodule Cantastic.OBD2.Service.Mode11 do
  @moduledoc false
  # ISO 14229-1 Mode 0x11 — ECUReset (UDS).
  #
  # Wire format:
  #   Request:  <<0x11, reset_type::8>>
  #   Response: <<0x51, reset_type::8>>  (positive ack, no payload)
  #
  # `reset_type` is taken from `request_specification.options.reset_type`,
  # defaulting to 0x01 (hardReset). Other common values:
  #   * 0x02 keyOffOnReset
  #   * 0x03 softReset
  #   * 0x04 enableRapidPowerShutDown
  #   * 0x05 disableRapidPowerShutDown
  #
  # No data parameters; positive responses surface as `parameters: %{}`.

  @behaviour Cantastic.OBD2.Service

  @default_reset_type 0x01

  @impl true
  def encode_request(request_specification) do
    reset_type = Map.get(request_specification.options || %{}, :reset_type, @default_reset_type)
    {:ok, <<request_specification.mode::big-integer-size(8), reset_type::big-integer-size(8)>>}
  end

  @impl true
  def decode_parameters(_request_specification, _raw_parameters) do
    {:ok, %{}}
  end
end
