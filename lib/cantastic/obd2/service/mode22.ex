defmodule Cantastic.OBD2.Service.Mode22 do
  @moduledoc false
  # ISO 14229-1 Mode 0x22 — ReadDataByIdentifier (UDS).
  #
  # Doorway to manufacturer-specific diagnostic data: every brand-specific DID
  # (Data Identifier) lives behind this service. DIDs are 16-bit and the
  # request can batch several at once, though many ECUs accept only one.
  #
  # Wire format:
  #   Request:  <<0x22, did::16, did::16, …>>
  #   Response: <<0x62, did::16, value, did::16, value, …>>
  #
  # `Cantastic` itself stays brand-agnostic: standard parameter kinds
  # (`decimal`, `integer`, `ascii`, `bytes`) cover the common payload shapes.
  # For brand-specific decoding (cell voltages, packed sensor arrays, etc.),
  # declare the parameter as `kind: "bytes"` and decode the raw payload
  # inside your response handler. See the `Cantastic.OBD2` moduledoc for the
  # full pattern.

  @behaviour Cantastic.OBD2.Service

  alias Cantastic.OBD2.Parameter

  @id_size 16

  @impl true
  def encode_request(request_specification) do
    payload =
      request_specification.parameter_specifications
      |> Enum.reduce(<<request_specification.mode::big-integer-size(8)>>, fn parameter_specification, acc ->
        <<acc::bitstring, parameter_specification.id::big-integer-size(@id_size)>>
      end)

    {:ok, payload}
  end

  @impl true
  def decode_parameters(request_specification, raw_parameters) do
    try do
      parameters =
        request_specification.parameter_specifications
        |> Enum.reduce(%{raw_parameters: raw_parameters}, fn parameter_specification, acc ->
          case Parameter.interpret(acc.raw_parameters, parameter_specification, @id_size) do
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
