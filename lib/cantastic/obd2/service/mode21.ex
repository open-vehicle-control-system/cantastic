defmodule Cantastic.OBD2.Service.Mode21 do
  @moduledoc false
  # ISO 14230-3 (KWP2000) Mode 0x21 — ReadDataByLocalIdentifier.
  #
  # Heavily used by Toyota / Lexus / Scion and a number of other older
  # Asian-platform ECUs. Wire format mirrors OBD2 Mode 0x01 with a different
  # SID; the "local identifier" is an 8-bit byte that addresses an ECU-
  # internal data slot (engine load, sensor reading, etc.). Multiple
  # identifiers may be batched in a single request, just like Mode 0x01.
  #
  # Wire format:
  #   Request:  <<0x21, lid::8, lid::8, …>>
  #   Response: <<0x61, lid::8, value, lid::8, value, …>>

  @behaviour Cantastic.OBD2.Service

  alias Cantastic.OBD2.Parameter

  @impl true
  def encode_request(request_specification) do
    payload =
      request_specification.parameter_specifications
      |> Enum.reduce(<<request_specification.mode::big-integer-size(8)>>, fn parameter_specification, acc ->
        <<acc::bitstring, parameter_specification.id::integer-size(8)>>
      end)

    {:ok, payload}
  end

  @impl true
  def decode_parameters(request_specification, raw_parameters) do
    try do
      parameters =
        request_specification.parameter_specifications
        |> Enum.reduce(%{raw_parameters: raw_parameters}, fn parameter_specification, acc ->
          case Parameter.interpret(acc.raw_parameters, parameter_specification) do
            {:ok, parameter, truncated} ->
              acc
              |> put_in([parameter.name], parameter)
              |> put_in([:raw_parameters], truncated)

            {:error, reason} ->
              throw({:decode_failed, parameter_specification.name, reason})
          end
        end)

      {:ok, parameters}
    catch
      {:decode_failed, _name, _reason} = err ->
        {:error, err}
    end
  end
end
