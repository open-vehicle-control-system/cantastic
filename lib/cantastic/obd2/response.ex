defmodule Cantastic.OBD2.Response do
  alias Cantastic.OBD2.Codec

  @moduledoc """
    `Cantastic.OBD2.Response` is a `Struct` used to represent one OBD2 response.

    The attributes are the following:

    * `:request_name` The OBD2 request's name, as defined in your YAML file.
    * `:mode` The OBD2 mode, as defined in your YAML file.
    * `:reception_timestamp`  The `DateTime` at which the frame was received by the kernel.
    * `:parameters` A `Map` of the parameters contained in this response.
  """

  @negative_response_sid 0x7F

  # ISO 14229-1 Annex A — common Negative Response Codes.
  @nrc_names %{
    0x10 => :general_reject,
    0x11 => :service_not_supported,
    0x12 => :sub_function_not_supported,
    0x13 => :incorrect_message_length_or_invalid_format,
    0x14 => :response_too_long,
    0x21 => :busy_repeat_request,
    0x22 => :conditions_not_correct,
    0x24 => :request_sequence_error,
    0x25 => :no_response_from_subnet_component,
    0x26 => :failure_prevents_execution_of_requested_action,
    0x31 => :request_out_of_range,
    0x33 => :security_access_denied,
    0x35 => :invalid_key,
    0x36 => :exceeded_number_of_attempts,
    0x37 => :required_time_delay_not_expired,
    0x70 => :upload_download_not_accepted,
    0x71 => :transfer_data_suspended,
    0x72 => :general_programming_failure,
    0x73 => :wrong_block_sequence_counter,
    0x78 => :request_correctly_received_response_pending,
    0x7E => :sub_function_not_supported_in_active_session,
    0x7F => :service_not_supported_in_active_session
  }

  defstruct [
    :request_name,
    :mode,
    :reception_timestamp,
    parameters: %{}
  ]

  @doc false
  def interpret(request_specification, socket_message) do
    case socket_message.raw do
      <<@negative_response_sid, sid::integer-size(8), nrc::integer-size(8), _rest::bitstring>> ->
        {:error, {:nrc, sid, nrc, Map.get(@nrc_names, nrc, :unknown_nrc)}}

      <<mode::integer-size(8), raw_parameters::bitstring>> ->
        decode_positive(request_specification, socket_message, mode, raw_parameters)

      _ ->
        {:error, {:malformed_response, socket_message.raw}}
    end
  end

  defp decode_positive(request_specification, socket_message, mode, raw_parameters) do
    case Codec.decode_parameters(request_specification, raw_parameters) do
      {:ok, parameters} ->
        response = %__MODULE__{
          request_name: request_specification.name,
          mode: mode,
          parameters: parameters,
          reception_timestamp: socket_message.reception_timestamp
        }

        {:ok, response}

      {:error, _reason} = err ->
        err
    end
  end
end
