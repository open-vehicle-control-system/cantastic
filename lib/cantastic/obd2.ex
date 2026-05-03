defmodule Cantastic.OBD2 do
  @moduledoc """
  OBD2, KWP2000 and UDS diagnostic services for `Cantastic`.

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

  | Mode | Service  | Standard            | Purpose                                     |
  |------|----------|---------------------|---------------------------------------------|
  | 0x01 | `Mode01` | SAE J1979           | Show current data (live PIDs)               |
  | 0x02 | `Mode02` | SAE J1979           | Show freeze frame data                      |
  | 0x03 | `Mode03` | SAE J1979           | Read stored DTCs                            |
  | 0x04 | `Mode04` | SAE J1979           | Clear emission DTCs                         |
  | 0x07 | `Mode07` | SAE J1979           | Read pending DTCs                           |
  | 0x09 | `Mode09` | SAE J1979           | Read vehicle information (VIN, cal IDs)     |
  | 0x0A | `Mode0A` | SAE J1979           | Read permanent DTCs                         |
  | 0x10 | `Mode10` | ISO 14229-1 (UDS)   | DiagnosticSessionControl                    |
  | 0x11 | `Mode11` | ISO 14229-1 (UDS)   | ECUReset                                    |
  | 0x14 | `Mode14` | ISO 14229-1 (UDS)   | ClearDiagnosticInformation                  |
  | 0x19 | `Mode19` | ISO 14229-1 (UDS)   | ReadDTCInformation                          |
  | 0x1A | `Mode1A` | ISO 14230-3 (KWP)   | ReadECUIdentification                       |
  | 0x21 | `Mode21` | ISO 14230-3 (KWP)   | ReadDataByLocalIdentifier                   |
  | 0x22 | `Mode22` | ISO 14229-1 (UDS)   | ReadDataByIdentifier (16-bit DIDs)          |
  | 0x2E | `Mode2E` | ISO 14229-1 (UDS)   | WriteDataByIdentifier                       |
  | 0x31 | `Mode31` | ISO 14229-1 (UDS)   | RoutineControl (start / stop / get result)  |
  | 0x3E | `Mode3E` | ISO 14229-1 (UDS)   | TesterPresent (session keepalive)           |

  ## YAML quick reference

  All requests share the same top-level shape:

      obd2_requests:
        - name: <atom-able string used to subscribe / enable>
          request_frame_id: <CAN id used to send the request>
          response_frame_id: <CAN id of the ECU's reply>
          frequency: <ms between automatic re-emissions>
          mode: 0x01 .. 0x3E
          parameters: [ … ]    # optional; depends on mode
          options: { … }       # optional; service-specific knobs

  Per-mode notes follow. Anything not mentioned in `:options` falls back to
  the default documented in the corresponding service module.

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
              id: 0x0D
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

  ### Mode 0x04 — clear emission DTCs

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

  ### Mode 0x10 — open a diagnostic session (UDS)

  Required before reading non-default DIDs or running routines on
  UDS-only ECUs. The response carries the session timing budget,
  surfaced as `parameters["p2_server_max_ms"]` and
  `parameters["p2_star_server_max_ms"]` so the caller can tune its
  TesterPresent interval to match.

      obd2_requests:
        - name: extended_session
          request_frame_id: 0x7E0
          response_frame_id: 0x7E8
          frequency: 5000
          mode: 0x10
          options:
            session_type: 0x03    # 0x03 extendedDiagnosticSession (default)

  ### Mode 0x11 — reset the ECU (UDS)

  No parameters. `options.reset_type` defaults to `0x01` (hardReset);
  other common values are `0x02` (keyOffOnReset) and `0x03` (softReset).

      obd2_requests:
        - name: reset_ecu
          request_frame_id: 0x7E0
          response_frame_id: 0x7E8
          frequency: 30000
          mode: 0x11
          options:
            reset_type: 0x01

  ### Mode 0x14 — clear DTCs (UDS)

  Modern equivalent of Mode 0x04. `options.group_of_dtc` is a 24-bit
  picker (default `0xFFFFFF`, "all DTCs").

      obd2_requests:
        - name: uds_clear_dtcs
          request_frame_id: 0x7E0
          response_frame_id: 0x7E8
          frequency: 5000
          mode: 0x14
          options:
            group_of_dtc: 0xFFFFFF

  ### Mode 0x19 — read DTC information (UDS)

  Modern equivalent of Mode 0x03. Each DTC comes back *with a status
  byte* (confirmed / pending / test-failed-since-last-clear …) plus a
  manufacturer-specific fault-type byte. Surfaced as a list of maps
  under `parameters["dtc_records"]`.

      obd2_requests:
        - name: uds_read_dtcs
          request_frame_id: 0x7E0
          response_frame_id: 0x7E8
          frequency: 1000
          mode: 0x19
          options:
            sub_function: 0x02    # reportDTCByStatusMask (default)
            status_mask: 0xFF     # match all status bits (default)

  Each item in `parameters["dtc_records"].value` is shaped
  `%{code: "P0301", fault_type: 0x00, status: 0x09}`.

  ### Mode 0x1A — KWP2000 ECU identification

  Used by Toyota / Lexus and several other manufacturers as their VIN
  / ECU info read in place of OBD2 Mode 0x09. Single byte
  identification option, ASCII payload.

      obd2_requests:
        - name: kwp_vin
          request_frame_id: 0x7E0
          response_frame_id: 0x7E8
          frequency: 5000
          mode: 0x1A
          parameters:
            - name: vin
              id: 0x90              # identification option byte
              kind: ascii
              value_length: 136     # 17 bytes × 8

  ### Mode 0x21 — KWP2000 read by local identifier

  Heavily used by Toyota / Lexus and older Asian-platform ECUs.
  Wire format mirrors Mode 0x01 with a different SID and 8-bit
  local identifiers. Multi-LID batches supported.

      obd2_requests:
        - name: kwp_engine_data
          request_frame_id: 0x7E0
          response_frame_id: 0x7E8
          frequency: 200
          mode: 0x21
          parameters:
            - name: engine_load
              id: 0x05
              kind: integer
              value_length: 8
              unit: "%"

  ### Mode 0x22 — UDS ReadDataByIdentifier

  16-bit DIDs. Multi-DID requests are allowed but most ECUs only honour
  a single DID per call.

      obd2_requests:
        - name: battery_state
          request_frame_id: 0x7E0
          response_frame_id: 0x7E8
          frequency: 500
          mode: 0x22
          parameters:
            - name: state_of_charge
              id: 0xF40D
              kind: integer
              value_length: 8
              unit: "%"

  ### Mode 0x2E — UDS WriteDataByIdentifier

  Pair to Mode 0x22. The DID comes from the single parameter's `id`;
  the bytes to write come from `options.data`.

      obd2_requests:
        - name: write_config
          request_frame_id: 0x7E0
          response_frame_id: 0x7E8
          frequency: 5000
          mode: 0x2E
          parameters:
            - name: config_word
              id: 0xF1A0
              kind: bytes
              value_length: 16
          options:
            data: !!binary "..."        # raw bytes to write

  ### Mode 0x31 — UDS RoutineControl

  Start / stop / query the result of an ECU routine (forced DPF
  regeneration, ABS bleed, throttle adaptation reset, …). The
  status_record returned is brand- and routine-specific, so it is
  surfaced as raw bytes under `parameters["routine_status"]`.

      obd2_requests:
        - name: start_dpf_regen
          request_frame_id: 0x7E0
          response_frame_id: 0x7E8
          frequency: 1000
          mode: 0x31
          options:
            routine_id: 0x0203        # required
            sub_function: 0x01        # 0x01 startRoutine (default)

  ### Mode 0x3E — UDS TesterPresent

  Sent periodically (typically every 2 s) to keep a non-default
  diagnostic session alive. `options.sub_function` defaults to `0x00`
  (zeroSubFunction, expects a positive response); set bit 7 (`0x80`)
  to suppress the ECU's positive response, which is the usual choice
  for high-frequency keepalives.

      obd2_requests:
        - name: tester_present
          request_frame_id: 0x7E0
          response_frame_id: 0x7E8
          frequency: 2000
          mode: 0x3E
          options:
            sub_function: 0x80        # suppressPosRespMsgIndicationBit

  ## Negative response handling

  If the ECU returns `<<0x7F, sid, nrc>>`, subscribers receive
  `{:handle_obd2_error, {:nrc, sid, code, name_atom}}` instead of
  `{:handle_obd2_response, _}`. The `name_atom` comes from a small
  ISO 14229-1 Annex A table (e.g. `:sub_function_not_supported`,
  `:request_out_of_range`, `:security_access_denied`, …). The request
  process stays alive and the next valid response from the same ECU is
  delivered normally.

  ## Brand-specific UDS without brand-specific code in cantastic

  Manufacturers expose hundreds of proprietary DIDs, routines and local
  identifiers. The philosophy here is that Cantastic provides the
  universal wire-format primitives and **never** embeds brand quirks.
  Two patterns keep brand-specific behaviour in your application:

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

  ## A typical real-world diagnostic session

  Diagnostic flows on a real car typically chain several services
  together. The orchestration is application-level — Cantastic gives
  you the building blocks. A common pattern (e.g. clearing a stubborn
  DTC on a modern UDS-only ECU):

  1. **Open an extended session** with Mode 0x10
     (`session_type: 0x03`). The ECU's response gives you `p2`
     timings; use them to size your TesterPresent cadence.
  2. **Start a TesterPresent loop** with Mode 0x3E at roughly half the
     ECU's `p2_server_max` (often ~2 s with a `sub_function: 0x80`
     suppress-positive-response).
  3. **Read DTCs** with Mode 0x19 (`sub_function: 0x02`) to confirm
     which faults are present. The status byte tells you whether each
     is confirmed, pending, or already-cleared-but-pending.
  4. *(Optional)* run **security access** if the ECU requires it for
     the next step. Cantastic does not yet ship a built-in service for
     Mode 0x27 because the seed→key derivation is brand-specific; you
     can do the handshake manually via `Cantastic.Socket` until
     Mode 0x27 lands with a `key_function` callback.
  5. **Clear DTCs** with Mode 0x14 (`group_of_dtc: 0xFFFFFF` for all).
  6. **Stop TesterPresent**, **leave the session** (Mode 0x10
     `session_type: 0x01`, defaultSession), and optionally **reset the
     ECU** with Mode 0x11.

  Vintage Toyota (and some Mitsubishi / Hyundai) needs a different
  flow:

  1. **Read ECU identification** with Mode 0x1A (`id: 0x90` for VIN).
  2. **Read live data** with Mode 0x21 — typical local identifiers are
     0x05 engine load, 0x07 throttle position, 0x0F battery voltage
     (varies per ECU; consult the platform's service manual).
  3. **OBD2 standard modes** (0x01 / 0x03 / 0x04) work in parallel for
     emission diagnostics; Toyota ECUs respond to both.

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
