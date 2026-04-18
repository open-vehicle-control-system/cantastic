defmodule Cantastic.ConfigurationStore do
  @moduledoc false

  use Agent

  def start_link(_) do
    networks = compute_networks()

    state = %{
      networks: networks,
      setup_can_interfaces: Application.get_env(:cantastic, :setup_can_interfaces) || false,
      socketcand_ip_interface:
        Application.get_env(:cantastic, :socketcand_ip_interface) || "eth0",
      enable_socketcand: Application.get_env(:cantastic, :enable_socketcand) || false
    }

    Agent.start_link(fn -> state end, name: __MODULE__)
  end

  def network_names() do
    Agent.get(__MODULE__, fn state ->
      state.networks
      |> Enum.map(fn network ->
        network.name
      end)
    end)
  end

  def networks() do
    Agent.get(__MODULE__, fn state ->
      state.networks
    end)
  end

  def socketcand_ip_interface() do
    Agent.get(__MODULE__, fn state ->
      state.socketcand_ip_interface
    end)
  end

  def enable_socketcand() do
    Agent.get(__MODULE__, fn state ->
      state.enable_socketcand
    end)
  end

  def setup_can_interfaces() do
    Agent.get(__MODULE__, fn state ->
      state.setup_can_interfaces
    end)
  end

  defp compute_networks() do
    {:ok, configuration} = read_configuration()

    can_network_mappings =
      case Application.get_env(:cantastic, :can_network_mappings) do
        nil ->
          throw("CAN network mappings are missing from the Cantastic configuratiion")

        [] ->
          throw(
            "You must define at least one CAN network mapping in the Cantastic configuratiion"
          )

        fun when is_function(fun) ->
          fun.()

        networks when is_list(networks) ->
          networks

        {module, function_name, params} ->
          apply(module, function_name, params)

        _ ->
          throw("CAN netowrk mappings is not valid in the Cantastic configuratiion")
      end

    Enum.map(can_network_mappings, fn can_network_mapping ->
      {network_name, interface, labels} =
        case can_network_mapping do
          {network_name, interface} -> {network_name, interface, []}
          {network_name, interface, labels: labels} -> {network_name, interface, labels}
        end

      network_name = network_name |> String.to_atom()
      network_configuration = configuration.can_networks[network_name]

      if is_nil(network_configuration) do
        throw(
          "[Yaml configuration error] CAN Network: '#{network_name}' is missing from the Yaml configuration."
        )
      end

      bitrate = network_configuration.bitrate

      %{
        network_name: network_name,
        interface: interface,
        network_config: network_configuration,
        bitrate: bitrate,
        labels: labels
      }
    end)
  end

  # `priv_can_config_path` may be a string (single YAML) or a list
  # of strings (multiple YAMLs merged together — useful when a
  # single BEAM hosts what would normally be separate firmwares,
  # e.g. running VMS + infotainment in one local-dev process).
  # Same-named networks are unioned; emitted/received frame lists
  # are concatenated and deduplicated.
  defp read_configuration() do
    otp_app = Application.get_env(:cantastic, :otp_app)

    paths =
      Application.get_env(:cantastic, :priv_can_config_path)
      |> List.wrap()

    priv_dir = :code.priv_dir(otp_app)

    Enum.reduce_while(paths, {:ok, %{can_networks: %{}}}, fn rel, {:ok, acc} ->
      case read_yaml(Path.join(priv_dir, rel)) do
        {:ok, cfg} -> {:cont, {:ok, merge_configurations(acc, cfg)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp merge_configurations(acc, cfg) do
    acc_networks = Map.get(acc, :can_networks, %{})
    new_networks = Map.get(cfg, :can_networks, %{})

    merged_networks =
      Map.merge(acc_networks, new_networks, fn _name, a, b ->
        %{
          bitrate: a[:bitrate] || b[:bitrate],
          emitted_frames:
            ((a[:emitted_frames] || []) ++ (b[:emitted_frames] || []))
            |> Enum.uniq(),
          received_frames:
            ((a[:received_frames] || []) ++ (b[:received_frames] || []))
            |> Enum.uniq()
        }
      end)

    %{acc | can_networks: merged_networks}
  end

  defp read_yaml(path) do
    with {:ok, config} <- YamlElixir.read_from_file(path, atoms: true, merge_anchors: true),
         {:ok, encoded} <- Jason.encode(config),
         {:ok, decoded} <- encoded |> Jason.decode(keys: :atoms) do
      base_path = path |> Path.dirname()
      interpret_node(base_path, decoded)
    else
      {:error, error} -> {:error, error}
    end
  end

  defp interpret_node(base_path, node) when is_map(node) do
    interpreted_node =
      node
      |> Enum.reduce(%{}, fn {key, value}, acc ->
        {:ok, interpreted_value} = interpret_node(base_path, value)
        acc |> Map.put(key, interpreted_value)
      end)

    {:ok, interpreted_node}
  end

  defp interpret_node(base_path, node) when is_list(node) do
    interpreted_node =
      node
      |> Enum.map(fn value ->
        {:ok, interpreted_value} = interpret_node(base_path, value)
        interpreted_value
      end)

    {:ok, interpreted_node}
  end

  defp interpret_node(base_path, "import!:" <> path) do
    full_path = resolve_import_path(base_path, path)
    read_yaml(full_path)
  end

  defp interpret_node(_, node), do: {:ok, node}

  defp resolve_import_path(_base_path, "@" <> rest) do
    [otp_app, relative] = String.split(rest, ":", parts: 2)
    Path.join(:code.priv_dir(String.to_atom(otp_app)), relative)
  end

  defp resolve_import_path(base_path, path), do: Path.join(base_path, path)
end
