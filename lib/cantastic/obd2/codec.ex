defmodule Cantastic.OBD2.Codec do
  @moduledoc false
  # Dispatches request encoding and response-payload decoding to the right
  # `Cantastic.OBD2.Service` implementation, keyed by the request mode.
  #
  # Modes without a dedicated service fall back to `Mode01`, which uses the
  # generic positional 8-bit-id layout. This preserves the lib's prior
  # behaviour for configurations that declare a non-Mode-0x01 mode.

  alias Cantastic.OBD2.Service.Mode01

  @services %{
    0x01 => Mode01
  }

  def encode_request(request_specification) do
    service(request_specification.mode).encode_request(request_specification)
  end

  def decode_parameters(request_specification, raw_parameters) do
    service(request_specification.mode).decode_parameters(request_specification, raw_parameters)
  end

  defp service(mode), do: Map.get(@services, mode, Mode01)
end
