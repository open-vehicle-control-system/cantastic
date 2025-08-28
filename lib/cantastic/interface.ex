defmodule Cantastic.Interface do
  alias Cantastic.{FrameSpecification, Receiver, Emitter, ConfigurationStore, ReceivedFrameWatcher, Socket, Util, OBD2}
  require Logger

  def configure_children() do
    interface_specs = ConfigurationStore.networks() |> Enum.map(fn (network) ->
      {:ok, socket} = initialize_socket(network.interface, network.bitrate, ConfigurationStore.setup_can_interfaces())
      Logger.info("CAN network: '#{network.network_name}' ready on interface: '#{network.interface}'")
      %{
        network_name: network.network_name,
        network_config: network.network_config,
        socket: socket,
        interface: network.interface
      }
    end)

    receivers_and_watchers = configure_receivers_and_watchers(interface_specs)
    emitters               = configure_emitters(interface_specs)
    obd2_requests          = configure_obd2_requests(interface_specs)
    receivers_and_watchers ++ emitters ++ obd2_requests
  end

  def configure_receivers_and_watchers(interface_specs) do
    interface_specs
    |> Enum.map(fn (%{network_name: network_name, network_config: network_config, socket: socket}) ->
      receiver_process_name         = receiver_process_name(network_name)
      received_frame_specifications = compute_frame_specifications((network_config[:received_frames] || []), network_name, :receive)
      watchers = received_frame_specifications
      |> Enum.map(fn({_id, frame_specification}) ->
        arguments = %{
          process_name: received_frame_watcher_process_name(network_name, frame_specification.name),
          frame_specification: frame_specification,
          network_name: network_name
        }
        Supervisor.child_spec({ReceivedFrameWatcher, arguments}, id: arguments.process_name)
      end)
      arguments = %{
        process_name: receiver_process_name,
        network_name: network_name,
        socket: socket,
        frame_specifications: received_frame_specifications
      }
      [Supervisor.child_spec({Receiver, arguments}, id: arguments.process_name)] ++ watchers
    end)
    |> List.flatten()
  end

  def configure_emitters(interface_specs) do
    interface_specs
    |> Enum.map(fn (%{network_name: network_name, network_config: network_config, socket: socket}) ->
      (network_config[:emitted_frames] || [])
      |> compute_frame_specifications(network_name, :emit)
      |> Enum.map(fn({_frame_id, frame_specification}) ->
        arguments = %{
          socket: socket,
          network_name: network_name,
          process_name: emitter_process_name(network_name, frame_specification.name),
          frame_specification: frame_specification
        }
        Supervisor.child_spec({Emitter, arguments}, id: arguments.process_name)
      end)
    end)
    |> List.flatten
  end

  def configure_obd2_requests(interface_specs) do
    interface_specs
    |> Enum.map(fn (%{network_name: network_name, network_config: network_config, interface: interface, socket: _socket}) ->
      (network_config[:obd2_requests] || [])
      |> Enum.map(fn(yaml_request_specification) ->
        {:ok, request_specification} = OBD2.RequestSpecification.from_yaml(network_name, interface, yaml_request_specification)
        arguments = %{
          process_name: obd2_request_process_name(network_name, request_specification.name),
          request_specification: request_specification
        }
        Supervisor.child_spec({OBD2.Request, arguments}, id: arguments.process_name)
      end)
    end)
    |> List.flatten
  end

  defp process_name_prefix(network_name) do
    network_name = network_name |> Atom.to_string()
    "Cantastic#{network_name |> Macro.camelize()}"
  end

  def receiver_process_name(network_name) do
    "#{process_name_prefix(network_name)}Receiver" |> String.to_atom
  end

  def emitter_process_name(network_name, frame_name) do
    "#{process_name_prefix(network_name)}#{frame_name |> Macro.camelize()}Emitter" |> String.to_atom
  end

  def obd2_request_process_name(network_name, request_name) do
    "#{process_name_prefix(network_name)}#{request_name |> Macro.camelize()}OBD2Request" |> String.to_atom
  end

  def received_frame_watcher_process_name(network_name, frame_name) do
    "#{process_name_prefix(network_name)}#{frame_name |> Macro.camelize()}ReceivedFrameWatcher" |> String.to_atom
  end

  defp initialize_socket(interface, bitrate, setup_can_interfaces) do
    case setup_can_interface(interface, bitrate, setup_can_interfaces) do
      :ok -> Socket.bind_raw(interface)
    end
  end

  # {800: name: "handbrakeStatus", signals: [{name: 'handbrakeEngaged', value: true, mapping: ....}, {name: 'handbrakeError': {value: true, ...}}]}
  defp compute_frame_specifications(yaml_frame_specifications, network_name, direction) do
    yaml_frame_specifications
    |> Enum.reduce(%{}, fn(yaml_frame_specification, frame_specifications) ->
      {:ok, frame_specification} = FrameSpecification.from_yaml(network_name, yaml_frame_specification, direction)
      if Map.has_key?(frame_specifications, frame_specification.id) do
        throw "[Yaml configuration error] frame id: 0x#{Util.integer_to_hex(frame_specification.id)} is duplicated, please ensure that you only use a frame ID once per network."
      end
      if Enum.find(frame_specifications, fn ({_id, fs}) -> fs.name == frame_specification.name end) do
        throw "[Yaml configuration error] frame name: '#{frame_specification.name}' is duplicated, please ensure that you only use a frame name once per network."
      end
      frame_specifications |> Map.put(frame_specification.id, frame_specification)
    end)
  end

  defp setup_can_interface(interface, bitrate, setup_can_interfaces, retry_number \\ 0)
  defp setup_can_interface(interface, _bitrate, _setup_can_interfaces, 40) do
    Logger.error("Could not open CAN bus interface #{interface}")
  end
  defp setup_can_interface(interface, _bitrate, false = _setup_can_interfaces, _retry_number) do
    Logger.debug("Connection to the CAN bus #{interface} skipped following can interface setup config")
    :ok
  end
  defp setup_can_interface(interface, bitrate, setup_can_interfaces, retry_number) when binary_part(interface, 0, 4) == "vcan" do
    with  {_output, 0} <- System.cmd("ip", ["link", "add", "dev", interface, "type", "vcan"]),
          {_output, 0} <- System.cmd("ip", ["link", "set", "up", interface]),
          {output, 0} <- System.cmd("ip", ["link", "show", interface]),
          false       <- output |> String.match?(~r/state DOWN/)
    do
      Logger.info("Connection to #{interface} initialized")
      :ok
    else
      _ -> Logger.warning("""
          Please enable virtual CAN bus interface: #{interface} manually with the following commands:
          $ sudo ip link add dev #{interface} type vcan
          $ sudo ip link set up #{interface}
          The applicaltion will start working once done
        """)
        :timer.sleep(1000)
        setup_can_interface(interface, bitrate, setup_can_interfaces, retry_number + 1)
    end
  end
  defp setup_can_interface(interface, bitrate, true = setup_can_interfaces, retry_number) do
    with  {_output, 0} <- System.cmd("ip", ["link", "set", interface, "type", "can", "bitrate", "#{bitrate}"], stderr_to_stdout: true),
          {_output, 0} <- System.cmd("ip", ["link", "set", interface, "txqueuelen", "1000"], stderr_to_stdout: true),
          {_output, 0} <- System.cmd("ip", ["link", "set", interface, "up"], stderr_to_stdout: true)
    do
      Logger.info("Connection to the CAN bus #{interface} with a  bitrate of #{bitrate} bit/seconds initialized")
      :ok
    else
      {"RTNETLINK answers: Operation not permitted\n", _} ->
        Logger.error("""
          The connection to the CAN bus interface #{interface} cannot be open.
          This system probably requires to setup the interface manually with sudo.
          You should then set the SETUP_CAN_INTERFACES env variable to "false"
        """)
        System.stop(1)
      {output, _} ->
        Logger.warning("The connection to the CAN bus interface #{interface} failed with the following reason: '#{output}'Retrying in 0.5 seconds.")
        :timer.sleep(500)
        setup_can_interface(interface, bitrate, setup_can_interfaces, retry_number + 1)
    end
  end
end
