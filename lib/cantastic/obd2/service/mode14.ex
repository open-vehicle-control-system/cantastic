defmodule Cantastic.OBD2.Service.Mode14 do
  @moduledoc false
  # ISO 14229-1 Mode 0x14 — ClearDiagnosticInformation (UDS).
  #
  # Modern equivalent of OBD2 Mode 0x04. Many post-2010 ECUs (especially
  # body / comfort modules) only respond to 0x14, not 0x04.
  #
  # Wire format:
  #   Request:  <<0x14, group_of_dtc::24>>
  #   Response: <<0x54>>
  #
  # `group_of_dtc` is a 24-bit value picking which DTCs to clear.
  # Common values:
  #   * 0xFFFFFF — all DTCs (default)
  #   * 0xFFFF33 — emission-related DTCs
  #   * 0xFFFF00 — powertrain DTCs
  #   * a specific DTC's 3-byte UDS form to clear just that code
  #
  # Override via `request_specification.options.group_of_dtc`.
  #
  # Refusals (engine running, security access required, conditions not
  # correct) come through as `{:handle_obd2_error, {:nrc, _, _, _}}` like
  # any other UDS service.

  @behaviour Cantastic.OBD2.Service

  @default_group_of_dtc 0xFFFFFF

  @impl true
  def encode_request(request_specification) do
    group_of_dtc = Map.get(request_specification.options || %{}, :group_of_dtc, @default_group_of_dtc)

    {:ok,
     <<request_specification.mode::big-integer-size(8),
       group_of_dtc::big-integer-size(24)>>}
  end

  @impl true
  def decode_parameters(_request_specification, _raw_parameters) do
    {:ok, %{}}
  end
end
