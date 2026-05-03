defmodule Cantastic.OBD2.Service.Mode3E do
  @moduledoc false
  # ISO 14229-1 Mode 0x3E — TesterPresent (UDS).
  #
  # Sent periodically (typically every 2 s) to keep a non-default diagnostic
  # session alive. Without a TesterPresent heartbeat the ECU drops back to
  # the default session and any DIDs / routines that required an extended
  # session become unavailable.
  #
  # Wire format:
  #   Request:  <<0x3E, sub_function::8>>
  #   Response: <<0x7E, sub_function::8>>  (or no response if sub-function
  #                                          has the suppressPosResp bit set)
  #
  # `sub_function` is taken from `request_specification.options.sub_function`,
  # defaulting to 0x00 (zeroSubFunction, expects a positive response).
  # Setting bit 7 (i.e. 0x80) suppresses the positive response from the ECU,
  # which is useful for high-frequency keepalives.

  @behaviour Cantastic.OBD2.Service

  @default_sub_function 0x00

  @impl true
  def encode_request(request_specification) do
    sub_function = Map.get(request_specification.options || %{}, :sub_function, @default_sub_function)
    {:ok, <<request_specification.mode::big-integer-size(8), sub_function::big-integer-size(8)>>}
  end

  @impl true
  def decode_parameters(_request_specification, _raw_parameters) do
    {:ok, %{}}
  end
end
