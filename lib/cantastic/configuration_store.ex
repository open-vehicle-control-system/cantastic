defmodule Cantastic.ConfigurationStore do
  use Agent

  def start_link(_) do
    networks = compute_networks()
    state = %{
      networks: networks,
      setup_can_interfaces: Application.get_env(:cantastic, :setup_can_interfaces) || false,
      socketcand_ip_interface: Application.get_env(:cantastic, :socketcand_ip_interface) || "eth0",
      enable_socketcand: Application.get_env(:cantastic, :enable_socketcand) || false,
    }
    Agent.start_link(fn -> state end, name: __MODULE__)
  end

  def network_names() do
    Agent.get(__MODULE__, fn(state) ->
      state.networks |> Enum.map(fn(network) ->
        network.name
      end)
    end)
  end

  def networks() do
    Agent.get(__MODULE__, fn(state) ->
      state.networks
    end)
  end

  def socketcand_ip_interface() do
    Agent.get(__MODULE__, fn(state) ->
      state.socketcand_ip_interface
    end)
  end

  def enable_socketcand() do
    Agent.get(__MODULE__, fn(state) ->
      state.enable_socketcand
    end)
  end

  def setup_can_interfaces() do
    Agent.get(__MODULE__, fn(state) ->
      state.setup_can_interfaces
    end)
  end

  defp compute_networks() do
    {:ok, configuration}        = read_configuration()
    can_network_mappings = case Application.get_env(:cantastic, :can_network_mappings) do
      nil -> throw "CAN network mappings are missing from the Cantastic configuratiion"
      [] -> throw "You must define at least one CAN network mapping in the Cantastic configuratiion"
      fun when is_function(fun) -> fun.()
      networks when is_list(networks) -> networks
      {module, function_name, params} -> apply(module, function_name, params)
      _ -> throw "CAN netowrk mappings is not valid in the Cantastic configuratiion"
    end

    Enum.map(can_network_mappings, fn ({network_name, interface}) ->
      network_name          = network_name |> String.to_atom()
      network_configuration = configuration.can_networks[network_name]
      if is_nil(network_configuration) do
         throw "[Yaml configuration error] CAN Network: '#{network_name}' is missing from the Yaml configuration."
      end
      bitrate               = network_configuration.bitrate
      %{
        network_name: network_name,
        interface: interface,
        network_config: network_configuration,
        bitrate: bitrate
      }
    end)
  end

  defp read_configuration() do
    opt_app              = Application.get_env(:cantastic, :otp_app)
    priv_can_config_path = Application.get_env(:cantastic, :priv_can_config_path)
    config_path          = Path.join(:code.priv_dir(opt_app), priv_can_config_path)
    read_yaml(config_path)
  end

  defp read_yaml(path) do
    with {:ok, config}  <- YamlElixir.read_from_file(path, atoms: true, merge_anchors: true),
         {:ok, encoded} <- Jason.encode(config),
         {:ok, decoded} <- encoded |> Jason.decode(keys: :atoms)
    do
      base_path = path |> Path.dirname()
      interpret_node(base_path, decoded)
    else
      {:error, error} -> {:error, error}
    end
  end

  defp interpret_node(base_path, node) when is_map(node) do
    interpreted_node = node |> Enum.reduce(%{}, fn({key, value}, acc) ->
      {:ok, interpreted_value} = interpret_node(base_path, value)
      acc |> Map.put(key, interpreted_value)
    end)
    {:ok, interpreted_node}
  end
  defp interpret_node(base_path, node) when is_list(node) do
    interpreted_node = node |> Enum.map(fn(value) ->
      {:ok, interpreted_value} = interpret_node(base_path, value)
      interpreted_value
    end)
    {:ok, interpreted_node}
  end
  defp interpret_node(base_path, "import!:" <> path) do
    full_path   = Path.join([base_path, path])
    read_yaml(full_path)
  end
  defp interpret_node(_, node), do: {:ok, node}
end
