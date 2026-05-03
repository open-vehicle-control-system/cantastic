defmodule Cantastic.OBD2.Service.Mode07 do
  @moduledoc false
  # SAE J1979 / ISO 15031-5 Mode 0x07 — request pending DTCs (intermittent
  # codes detected since the last clear).
  #
  # Wire format is identical to Mode 0x03 with the SID shifted by 4: the
  # response is `<<0x47, count::8, dtc::16, …>>`.

  @behaviour Cantastic.OBD2.Service

  alias Cantastic.DTC
  alias Cantastic.OBD2.Parameter

  @impl true
  def encode_request(request_specification) do
    {:ok, <<request_specification.mode::big-integer-size(8)>>}
  end

  @impl true
  def decode_parameters(request_specification, <<_count::8, payload::bitstring>>) do
    with {:ok, codes} <- DTC.decode_list(payload) do
      parameter = %Parameter{
        name: "dtcs",
        request_name: request_specification.name,
        kind: "dtc_list",
        value: codes,
        raw_value: payload
      }

      {:ok, %{"dtcs" => parameter}}
    end
  end

  def decode_parameters(_request_specification, _raw_parameters) do
    {:error, :malformed_dtc_response}
  end
end
