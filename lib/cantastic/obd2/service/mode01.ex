defmodule Cantastic.OBD2.Service.Mode01 do
  @moduledoc false
  # SAE J1979 Mode 0x01 — show current data.
  #
  # Request layout:  <<0x01, pid_1::8, pid_2::8, …>>
  # Response layout: <<0x41, pid_1, raw_value_1::value_length_1, pid_2, …>>
  #
  # Several PIDs may be batched in one request; the response echoes each PID
  # before its value. This same positional 8-bit-id layout is used as the
  # default for any mode that doesn't have a dedicated service yet.

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
      {:decode_failed, _parameter_name, _reason} = err ->
        {:error, err}
    end
  end
end
