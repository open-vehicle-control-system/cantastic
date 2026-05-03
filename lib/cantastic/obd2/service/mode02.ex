defmodule Cantastic.OBD2.Service.Mode02 do
  @moduledoc false
  # SAE J1979 / ISO 15031-5 Mode 0x02 — show freeze frame data.
  #
  # When an emission-related DTC is set, the ECU captures a snapshot of
  # selected PIDs at that moment (vehicle speed, RPM, throttle, fuel trim,
  # etc.). Mode 0x02 reads that snapshot back.
  #
  # Request:  <<0x02, pid, frame_no, …>>
  # Response: <<0x42, pid, frame_no, value, …>>
  #
  # `frame_no` identifies which stored freeze frame to read; most ECUs only
  # store frame number 0 (the snapshot taken when the most recent emission-
  # related DTC was set). For now this service always asks for frame 0; a
  # YAML-level `frame_number` option can be added later if needed.
  #
  # PID semantics (value layout, scale, unit) are identical to Mode 0x01,
  # so the existing `Cantastic.OBD2.ParameterSpecification` is reused.

  @behaviour Cantastic.OBD2.Service

  alias Cantastic.OBD2.Parameter

  @frame_number 0

  @impl true
  def encode_request(request_specification) do
    payload =
      request_specification.parameter_specifications
      |> Enum.reduce(<<request_specification.mode::big-integer-size(8)>>, fn parameter_specification, acc ->
        <<acc::bitstring, parameter_specification.id::integer-size(8), @frame_number::integer-size(8)>>
      end)

    {:ok, payload}
  end

  @impl true
  def decode_parameters(request_specification, raw_parameters) do
    try do
      parameters =
        request_specification.parameter_specifications
        |> Enum.reduce(%{raw_parameters: raw_parameters}, fn parameter_specification, acc ->
          case strip_frame_number(acc.raw_parameters) do
            {:ok, without_frame_no} ->
              case Parameter.interpret(without_frame_no, parameter_specification) do
                {:ok, parameter, truncated} ->
                  acc
                  |> put_in([parameter.name], parameter)
                  |> put_in([:raw_parameters], truncated)

                {:error, reason} ->
                  throw({:decode_failed, parameter_specification.name, reason})
              end

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

  # Mode 0x02 sandwiches a frame-number byte between each PID and its value:
  #   <<pid::8, frame_no::8, value::bitstring, rest::bitstring>>
  # Strip the frame_no so the remaining buffer can be fed to the standard
  # `Parameter.interpret/2`, which expects `<<pid, value, rest>>`.
  defp strip_frame_number(<<pid::integer-size(8), _frame_no::integer-size(8), payload::bitstring>>) do
    {:ok, <<pid::integer-size(8), payload::bitstring>>}
  end

  defp strip_frame_number(_other), do: {:error, :malformed_freeze_frame_response}
end
