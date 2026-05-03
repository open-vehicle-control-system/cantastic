defmodule Cantastic.OBD2.Service do
  @moduledoc false
  # Behaviour implemented by per-mode codecs (Mode 0x01, 0x09, 0x22, …).
  #
  # `encode_request/1` returns the bytes that go on the bus for a given
  # request specification, starting with the OBD2 mode byte.
  #
  # `decode_parameters/2` takes the response payload (everything after the
  # response mode byte, i.e. after `request.mode + 0x40` for positive
  # responses) and turns it into a map of `name => Cantastic.OBD2.Parameter`.

  @callback encode_request(request_specification :: map()) ::
              {:ok, binary()} | {:error, term()}

  @callback decode_parameters(request_specification :: map(), raw_parameters :: bitstring()) ::
              {:ok, map()} | {:error, term()}
end
