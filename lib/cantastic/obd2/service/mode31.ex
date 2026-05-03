defmodule Cantastic.OBD2.Service.Mode31 do
  @moduledoc false
  # ISO 14229-1 Mode 0x31 — RoutineControl (UDS).
  #
  # Start / stop / query the result of an ECU routine: forced DPF
  # regeneration, ABS bleed, throttle adaptation reset, learned-value clear,
  # brake-pad service mode, and so on. Routines are identified by a 16-bit
  # `routine_id` and operated on via a sub-function byte:
  #
  #   * 0x01 startRoutine
  #   * 0x02 stopRoutine
  #   * 0x03 requestRoutineResults
  #
  # Wire format:
  #   Request:  <<0x31, sub_function::8, routine_id::16, input::bitstring>>
  #   Response: <<0x71, sub_function::8, routine_id::16, status::bitstring>>
  #
  # Options:
  #   * `routine_id`   — required; no sensible default
  #   * `sub_function` — defaults to `0x01` (startRoutine)
  #   * `input_data`   — optional binary appended after the routine id
  #
  # The response's `status_record` is brand- and routine-specific, so
  # cantastic surfaces it untouched as a single `kind: "bytes"` parameter
  # under `parameters["routine_status"]`. Decode it however your routine
  # documents it inside your own response handler.

  @behaviour Cantastic.OBD2.Service

  alias Cantastic.OBD2.Parameter

  @default_sub_function 0x01

  @impl true
  def encode_request(request_specification) do
    options = request_specification.options || %{}
    sub_function = Map.get(options, :sub_function, @default_sub_function)
    routine_id = Map.get(options, :routine_id)
    input_data = Map.get(options, :input_data, <<>>)

    cond do
      is_nil(routine_id) ->
        {:error, :mode_31_requires_routine_id_in_options}

      true ->
        {:ok,
         <<request_specification.mode::big-integer-size(8),
           sub_function::big-integer-size(8),
           routine_id::big-integer-size(16),
           input_data::bitstring>>}
    end
  end

  @impl true
  def decode_parameters(request_specification, raw_parameters) do
    case raw_parameters do
      <<_sub_function::big-integer-size(8),
        _routine_id::big-integer-size(16),
        status_record::bitstring>> ->
        parameter = %Parameter{
          name: "routine_status",
          request_name: request_specification.name,
          kind: "bytes",
          value: status_record,
          raw_value: status_record
        }

        {:ok, %{"routine_status" => parameter}}

      _ ->
        {:error, :malformed_mode_31_response}
    end
  end
end
