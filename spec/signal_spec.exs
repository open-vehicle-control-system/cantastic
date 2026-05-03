defmodule Cantastic.SignalSpec do
  use ESpec
  alias Cantastic.Signal
  alias Decimal, as: D

  describe ".to_string/1" do
    it "renders integer signals with frame name and value" do
      signal = %Signal{name: "rpm", frame_name: "engine", value: 2500, unit: "RPM", kind: "integer"}
      expect(Signal.to_string(signal)) |> to(eq("[Signal] engine.rpm = 2500"))
    end

    it "renders decimal signals with frame name and value" do
      signal = %Signal{name: "speed", frame_name: "obd2", value: D.new("25.5"), unit: "km/h", kind: "decimal"}
      expect(Signal.to_string(signal)) |> to(eq("[Signal] obd2.speed = 25.5"))
    end
  end
end
