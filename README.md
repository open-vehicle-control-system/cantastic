# Cantastic

Cantastic is an Elixir library to interact with CAN/Bus via lib_socket_can (Linux only).
It does all the heavy lifting of parsing the incoming frames and sending the outgoing ones at the right frequencies.

RAW and ISOTP modes are currently supported, BCM (Broadcast Manager) support is planned.

## Installation

in the `mix.exs` file:

```elixir
def deps do
  [{:cantastic, "~> 1.0.0"}]
end
```

## OTP App Configuration

### Example

```elixir
config :cantastic,
  can_network_mappings: "ovcs:vcan0,leaf_drive:vcan1,polo_drive:vcan2",
  setup_can_interfaces: true,
  otp_app: :vms_core,
  priv_can_config_path: "polo_2007.yml",
  enable_socketcand: true,
  socketcand_ip_interface: "wlan0"
```

## Description

Cantastic supports the following configuration options:

| Key | Description | Default value |
|-----|-------------|---------------|
| `:can_network_mappings` | A comma separated list of can network names and related interfaces. |  |
| `:setup_can_interfaces`| Wheher Cantastic should setup the CAN interfaces. It requires the Elixir user to have the approriate rights (usually the case for Nerves hosts). | `false` |
| `:otp_app` | The name of the OTP app owning the priv directory where the can config file is stored |  |
| `:priv_can_config_path` | The relative path where the Yaml config file is located |  |
| `:enable_socketcand` | Wheter Cantastic should start the socketcand server on all configured interfaces. This allows to remotely access the CAN interfaces for debugging.| `false` |
| `:socketcand_ip_interface` | The IP interface on which socketcand should listen to. | `"eth0"` |

## YAML configuration file

Cantastic requires you to define a YAML file describing the frames to be sent and received and how to interpret them.
This allows you to declaratively define your CAN networks in a clear and maintainable format.

### Example

```yaml
---
can_networks:
  ovcs:
    bitrate: 500000
    emitted_frames:
      - name: contactors_status_request
        id: 0x100
        frequency: 20
        signals:
          - name: main_negative_contactor_enabled
            kind: enum
            value_start: 0
            value_length: 8
            mapping:
              0x00: false
              0x01: true
          - name: main_positive_contactor_enabled
            kind: enum
            value_start: 8
            value_length: 8
            mapping:
              0x00: false
              0x01: true
    received_frames:
      - name: car_controls_status
        id: 0x200
        frequency: 10
        signals:
          - name: raw_max_throttle
            kind: integer
            value_start: 0
            value_length: 16
          - name: raw_throttle
            kind: integer
            value_start: 16
            value_length: 16
          - name: requested_gear
            kind: enum
            value_start: 48
            value_length: 8
            mapping:
              0x00: drive
              0x01: neutral
              0x02: reverse
              0x03: parking
```

### Detailed YAML file structure:

#### Top level property

| Key | Description | Required | Default value |
|-----|-------------|----------|---------------|
| `:can_networks` | a map of can networks to connect to in the form `network_name: {...network definitions...}` | True | |

#### Network properties

| Key | Description | Required | Default value |
|-----|-------------|----------|---------------|
| `:bitrate` | The CAN network speed in bits per seconds. | True |  |
| `:emitted_frames` | An array of frame definitions. | False | [] |
| `:received_frames` | An array of frame definitions.  | False | [] |
| `:obd2_requests` | An array of OBD2 request definitions. | False | [] |

##### Example

```YAML
#  my_vehicle.yml
---
can_networks:
  my_network:
    bitrate: 500000
    emitted_frames:
      - name: frame1
      - .....
    received_frames:
      - name: frame2
        ....
    obd2_requests:
      - name: request1
      - ....
```

#### Frame definition properties

| Key | Description | Required | Default value |
|-----|-------------|----------|---------------|
| `:id` | The CAN Frame ID | True | |
| `:name` | The CAN Frame name, will be used in your own code to reference it | True |  |
| `:frequency` | The frequency is milliseconds at which the frame should be emitted/is expected to be received | True for emitted frames, False for received frames |  |
| `:allowed_frequency_leeway` | The tolerance in milliseconds to be added to the frequency by the `Cantastic.ReceivedFrameWatcher` when monitoring the frame frequency | False | 10 |
| `:allowed_missing_frames` | The number of missed frames before `Cantastic.ReceivedFrameWatcher` should send `handle_missing_frame` messages to subscribers | False | 5 |
| `:allowed_missing_frames_period` | Timeframe in milliseconds during which `Cantastic.ReceivedFrameWatcher` is counting the number of missing frames | False | 5_000 |
| `:required_on_time_frames` | The number of frames received at the expected frequency to consider a frame back to 'normal' | false | 5 |
| `:signals` | An array of signals to be interpreted in this frame | False | [] |

#### OBD2 request definitions



#### Utilities

In order to keep your YAML file maintainable, Cantastic allows you to split it in multiple files and to import them using the following syntax:

`import!:ovcs_mini/generic_controller/0x701_main_controller_alive.yml`

##### Example:

```YAML
#  my_vehicle.yml
---
can_networks:
  ovcs:
    bitrate: 500000
    emitted_frames:
      - import!:./frames/frame1.yml
      - ...
    received_frames:
      - import!:./frames/frame2.yml
      - ...
    obd2_requests:
      - import!:./obd2_requests/frame2.yml
      - ....
```

```YAML
#  frames/frame1.yml
TODO
```
