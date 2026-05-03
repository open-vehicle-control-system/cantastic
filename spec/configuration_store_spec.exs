defmodule Cantastic.ConfigurationStoreSpec do
  use ESpec
  alias Cantastic.ConfigurationStore

  @fixtures_dir Path.expand("fixtures", __DIR__)

  describe ".read_yaml/1" do
    context "for a minimal config" do
      let :result, do: ConfigurationStore.read_yaml(Path.join(@fixtures_dir, "minimal.yml"))

      it "returns the decoded YAML as a map keyed by atoms" do
        {:ok, config} = result()
        expect(config.can_networks.ovcs.bitrate) |> to(eq(500_000))
        [frame] = config.can_networks.ovcs.received_frames
        expect(frame.name) |> to(eq("battery_status"))
        expect(frame.id) |> to(eq(0x100))
        expect(frame.frequency) |> to(eq(100))
        [signal] = frame.signals
        expect(signal.name) |> to(eq("voltage"))
        expect(signal.value_start) |> to(eq(0))
        expect(signal.value_length) |> to(eq(16))
        expect(signal.kind) |> to(eq("integer"))
      end
    end

    context "for a config that imports another YAML by relative path" do
      let :result, do: ConfigurationStore.read_yaml(Path.join(@fixtures_dir, "with_imports.yml"))

      it "inlines the imported file's contents at the import! site" do
        {:ok, config} = result()
        [frame] = config.can_networks.ovcs.received_frames
        expect(frame.name) |> to(eq("imported_frame"))
        expect(frame.id) |> to(eq(0x200))
        expect(frame.frequency) |> to(eq(50))
        [signal] = frame.signals
        expect(signal.name) |> to(eq("imported_signal"))
      end
    end
  end
end
