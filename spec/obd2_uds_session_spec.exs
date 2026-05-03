defmodule Cantastic.OBD2.UdsSessionSpec do
  use ESpec
  alias Cantastic.OBD2.{Request, RequestSpecification, Response}
  alias Cantastic.{SocketMessage, FakeSocket}

  defp request_spec(name, mode, options \\ %{}) do
    %RequestSpecification{
      name: name,
      request_frame_id: 0x7E0,
      response_frame_id: 0x7E8,
      frequency: 100,
      mode: mode,
      parameter_specifications: [],
      can_interface: "vcan_test",
      options: options
    }
  end

  defp start(name, mode, options \\ %{}) do
    process_name = String.to_atom("CantasticTestNetwork#{Macro.camelize(name)}OBD2Request")

    {:ok, pid} =
      Request.start_link(%{
        process_name: process_name,
        request_specification: request_spec(name, mode, options)
      })

    pid
  end

  defp shutdown(pid) do
    if Process.alive?(pid) do
      Process.unlink(pid)
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        500 -> :ok
      end
    end
  end

  before do
    allow(Cantastic.Socket)
    |> to(
      accept(:bind_isotp, fn _iface, _req_id, _resp_id, _padding ->
        {:ok, :fake_isotp_socket}
      end)
    )

    allow(Cantastic.Socket)
    |> to(
      accept(:send, fn _socket, raw ->
        FakeSocket.record_send(raw)
        :ok
      end)
    )

    allow(Cantastic.Socket)
    |> to(
      accept(:receive_message, fn _socket ->
        raw = FakeSocket.pop_recv()
        {:ok, %SocketMessage{raw: raw, reception_timestamp: 0}}
      end)
    )

    :ok
  end

  describe "resetting the ECU (Mode 0x11)" do
    context "with the default reset type" do
      it "sends 0x11 followed by 0x01 (hardReset)" do
        pid = start("ecu_reset", 0x11)

        try do
          :ok = Request.subscribe(self(), :test_network, "ecu_reset")
          FakeSocket.push_recv(<<0x51, 0x01>>)
          :ok = Request.enable(:test_network, "ecu_reset")

          assert_receive {:handle_obd2_response, %Response{mode: 0x51, parameters: %{}}}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x11, 0x01>>))
        after
          shutdown(pid)
        end
      end
    end

    context "with an explicit reset_type from options" do
      it "uses that byte instead of the default" do
        pid = start("ecu_reset", 0x11, %{reset_type: 0x03})

        try do
          :ok = Request.subscribe(self(), :test_network, "ecu_reset")
          FakeSocket.push_recv(<<0x51, 0x03>>)
          :ok = Request.enable(:test_network, "ecu_reset")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x11, 0x03>>))
        after
          shutdown(pid)
        end
      end
    end

    context "when the ECU rejects the reset" do
      it "delivers a :handle_obd2_error and stays alive" do
        pid = start("ecu_reset", 0x11)

        try do
          :ok = Request.subscribe(self(), :test_network, "ecu_reset")
          FakeSocket.push_recv(<<0x7F, 0x11, 0x22>>)
          :ok = Request.enable(:test_network, "ecu_reset")

          assert_receive {:handle_obd2_error, {:nrc, 0x11, 0x22, :conditions_not_correct}}, 1_000
          expect(Process.alive?(pid)) |> to(be_true())
        after
          shutdown(pid)
        end
      end
    end
  end

  describe "opening an extended session (Mode 0x10)" do
    context "with the default session type" do
      it "sends 0x10 followed by 0x03 (extendedDiagnosticSession)" do
        pid = start("session_open", 0x10)

        try do
          :ok = Request.subscribe(self(), :test_network, "session_open")
          # Response: <<0x50, 0x03, 0x00 0x32 (p2=50ms), 0x01 0xF4 (p2_star=5000ms)>>
          FakeSocket.push_recv(<<0x50, 0x03, 0x00, 0x32, 0x01, 0xF4>>)
          :ok = Request.enable(:test_network, "session_open")

          assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x10, 0x03>>))
          expect(parameters["p2_server_max_ms"].value) |> to(eq(50))
          expect(parameters["p2_star_server_max_ms"].value) |> to(eq(5000))
        after
          shutdown(pid)
        end
      end
    end

    context "with an explicit session_type from options" do
      it "uses that byte instead of the default" do
        pid = start("session_open", 0x10, %{session_type: 0x02})

        try do
          :ok = Request.subscribe(self(), :test_network, "session_open")
          FakeSocket.push_recv(<<0x50, 0x02, 0x00, 0x14, 0x00, 0x64>>)
          :ok = Request.enable(:test_network, "session_open")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x10, 0x02>>))
        after
          shutdown(pid)
        end
      end
    end
  end

  describe "keeping a session alive (Mode 0x3E TesterPresent)" do
    context "with the default sub-function (zeroSubFunction)" do
      it "sends 0x3E 0x00" do
        pid = start("tester_present", 0x3E)

        try do
          :ok = Request.subscribe(self(), :test_network, "tester_present")
          FakeSocket.push_recv(<<0x7E, 0x00>>)
          :ok = Request.enable(:test_network, "tester_present")

          assert_receive {:handle_obd2_response, %Response{mode: 0x7E, parameters: %{}}}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x3E, 0x00>>))
        after
          shutdown(pid)
        end
      end
    end

    context "with the suppressPosRespMsgIndicationBit set (sub_function 0x80)" do
      it "sends 0x3E 0x80" do
        pid = start("tester_present_suppressed", 0x3E, %{sub_function: 0x80})

        try do
          :ok = Request.subscribe(self(), :test_network, "tester_present_suppressed")
          # Even with suppressed positive response, the test pushes a synthetic
          # one so the request cycle completes; real ECUs would simply not reply.
          FakeSocket.push_recv(<<0x7E, 0x80>>)
          :ok = Request.enable(:test_network, "tester_present_suppressed")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x3E, 0x80>>))
        after
          shutdown(pid)
        end
      end
    end
  end
end
