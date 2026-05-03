defmodule Cantastic.OBD2 do
  @moduledoc """
  OBD2 and UDS diagnostic services for `Cantastic`.

  This module is documentation-only — the actual runtime entry point is
  `Cantastic.OBD2.Request` (subscribe / enable / disable). Read this page
  first to understand the YAML structure for diagnostic requests, the
  services Cantastic supports out of the box, and the pattern for using
  Cantastic with brand-specific UDS without putting brand code into the
  library itself.

  ## Supported services

  Each diagnostic request you declare in YAML carries a `mode` byte and is
  routed to the matching `Cantastic.OBD2.Service` implementation by
  `Cantastic.OBD2.Codec`. Modes without a registered service fall back to
  the Mode 0x01 generic positional codec.

  | Mode | Service       | Standard               | Purpose                                  |
  |------|---------------|------------------------|------------------------------------------|
  | 0x01 | `Mode01`      | SAE J1979              | Show current data (live PIDs)            |
  | 0x02 | `Mode02`      | SAE J1979              | Show freeze frame data                   |
  | 0x03 | `Mode03`      | SAE J1979              | Read stored DTCs                         |
  | 0x04 | `Mode04`      | SAE J1979              | Clear DTCs and stored values             |
  | 0x07 | `Mode07`      | SAE J1979              | Read pending DTCs                        |
  | 0x09 | `Mode09`      | SAE J1979              | Read vehicle information (VIN, cal IDs)  |
  | 0x0A | `Mode0A`      | SAE J1979              | Read permanent DTCs                      |
  | 0x22 | `Mode22`      | ISO 14229-1 (UDS)      | Read DataByIdentifier (16-bit DIDs)      |

  ## YAML quick reference

  All requests share the same top-level shape:

      obd2_requests:
        - name: <atom-able string used to subscribe / enable>
          request_frame_id: <CAN id used to send the request>
          response_frame_id: <CAN id of the ECU's reply>
          frequency: <ms between automatic re-emissions>
          mode: 0x01 .. 0x22
          parameters: [ … ]    # what to read; shape depends on mode

  Per-mode notes:

  ### Mode 0x01 — current data (live PIDs)

  Multi-PID requests are supported; the response packs each PID's value
  positionally.

      obd2_requests:
        - name: current_speed_and_rpm
          request_frame_id: 0x7DF
          response_frame_id: 0x7E8
          frequency: 100
          mode: 0x01
          parameters:
            - name: speed
              id: 0x0D            # 8-bit PID
              kind: integer
              value_length: 8
              unit: km/h
            - name: rpm
              id: 0x0C
              kind: decimal
              value_length: 16
              scale: "0.25"
              unit: rpm

  ### Mode 0x02 — freeze frame data

  Same parameter shape as Mode 0x01; the wire format adds a frame-number
  byte that Cantastic sets to `0` (the snapshot tied to the most recent
  fault).

  ### Mode 0x03 / 0x07 / 0x0A — read DTCs

  No parameters needed. The decoded `Response.parameters["dtcs"].value` is
  a list of `"P0301"`-style strings.

      obd2_requests:
        - name: stored_dtcs
          request_frame_id: 0x7DF
          response_frame_id: 0x7E8
          frequency: 1000
          mode: 0x03

  ### Mode 0x04 — clear DTCs

  No parameters. A positive response means the ECU accepted the clear; if
  it refuses (engine running, security access required, etc.) subscribers
  receive `{:handle_obd2_error, {:nrc, …}}` instead.

  ### Mode 0x09 — vehicle info

  Single PID per request. The decoded `:value` is *always* a list (length
  matches the response's `num_items` byte) so the caller doesn't have to
  branch on the PID.

      obd2_requests:
        - name: vehicle_info_vin
          request_frame_id: 0x7DF
          response_frame_id: 0x7E8
          frequency: 1000
          mode: 0x09
          parameters:
            - name: vin
              id: 0x02
              kind: ascii
              value_length: 136   # 17 bytes × 8

  ### Mode 0x22 — UDS ReadDataByIdentifier

  16-bit DIDs. Multi-DID requests are allowed but most ECUs only honour a
  single DID per call.

      obd2_requests:
        - name: battery_state
          request_frame_id: 0x7E0
          response_frame_id: 0x7E8
          frequency: 500
          mode: 0x22
          parameters:
            - name: state_of_charge
              id: 0xF40D            # 16-bit DID
              kind: integer
              value_length: 8
              unit: "%"

  ## Negative response handling

  If the ECU returns `<<0x7F, sid, nrc>>`, subscribers receive
  `{:handle_obd2_error, {:nrc, sid, code, name_atom}}` instead of
  `{:handle_obd2_response, _}`. The `name_atom` comes from a small
  ISO 14229-1 Annex A table (e.g. `:sub_function_not_supported`,
  `:request_out_of_range`, `:security_access_denied`, …). The request
  process stays alive and the next valid response from the same ECU is
  delivered normally.

  ## Brand-specific UDS without brand-specific code in cantastic

  Manufacturers expose hundreds of proprietary DIDs and routines. The
  philosophy here is that Cantastic provides the universal wire-format
  primitives and **never** embeds brand quirks. There are three patterns
  that keep brand-specific behaviour in your application:

  ### 1. Use `kind: "bytes"` for proprietary payload layouts

  When a single DID returns a packed structure that isn't a plain integer
  or string (cell voltages, sensor arrays, status bitfields, …), declare
  the parameter as `kind: "bytes"`. Cantastic surfaces the raw payload as
  the parameter's `:value` and your response handler decodes it however it
  needs to.

      # YAML
      obd2_requests:
        - name: leaf_battery
          mode: 0x22
          request_frame_id: 0x79B
          response_frame_id: 0x7BB
          frequency: 1000
          parameters:
            - name: cells
              id: 0x0002
              kind: bytes
              value_length: 1536    # 96 cells × 16 bits

      # Your application code
      def handle_info({:handle_obd2_response, %Cantastic.OBD2.Response{parameters: %{"cells" => p}}}, state) do
        voltages = MyApp.LeafBattery.decode_cells(p.value)
        # …
      end

  Brand knowledge stays where it belongs — in your app.

  ### 2. Read the raw value off any `Parameter`

  Every `Cantastic.OBD2.Parameter` carries both `:value` (decoded per
  `:kind`) and `:raw_value` (the bitstring as it came off the wire). If
  you need a different interpretation than the YAML provides, reach for
  `:raw_value` and decode it yourself.

  ### 3. Send arbitrary single-byte modes for one-off services

  Modes such as 0x10 (DiagnosticSessionControl) or 0x3E (TesterPresent)
  aren't yet shipped as dedicated services. Until they are, you can
  declare them under Mode 0x01's positional layout if the ECU's response
  is shaped that way, or subscribe directly to the underlying
  `Cantastic.Socket` to send raw frames. Dedicated services for the
  remaining standard UDS modes are planned and will be added without
  changing the YAML you already have.

  ## Subscribing to responses

  Once a request is declared in YAML and the application has started:

      :ok = Cantastic.OBD2.Request.subscribe(self(), :my_network, "leaf_battery")
      :ok = Cantastic.OBD2.Request.enable(:my_network, "leaf_battery")

  The subscribing process receives:

  * `{:handle_obd2_response, %Cantastic.OBD2.Response{}}` on each
    successful round-trip, or
  * `{:handle_obd2_error, reason}` when the ECU returns a negative
    response or the payload can't be decoded.

  Stop the periodic emission with
  `Cantastic.OBD2.Request.disable(:my_network, "leaf_battery")`.
  """
end
