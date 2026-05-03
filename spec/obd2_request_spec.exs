defmodule Cantastic.OBD2.RequestSpec do
  use ESpec
  alias Cantastic.OBD2.{Request, RequestSpecification, ParameterSpecification, Response}
  alias Cantastic.{SocketMessage, FakeSocket}
  alias Decimal, as: D

  @request_process_name :CantasticTestNetworkCurrentSpeedOBD2Request

  defp speed_parameter_spec do
    %ParameterSpecification{
      name: "speed",
      id: 0x0D,
      kind: "integer",
      precision: 0,
      network_name: :test_network,
      request_name: "current_speed",
      value_length: 8,
      endianness: "big",
      unit: "km/h",
      scale: D.new(1),
      offset: D.new(0),
      sign: "unsigned"
    }
  end

  defp rpm_parameter_spec do
    %ParameterSpecification{
      name: "rpm",
      id: 0x0C,
      kind: "decimal",
      precision: 2,
      network_name: :test_network,
      request_name: "current_speed",
      value_length: 16,
      endianness: "big",
      unit: "rpm",
      scale: D.new("0.25"),
      offset: D.new(0),
      sign: "unsigned"
    }
  end

  defp request_spec(parameters, frequency) do
    %RequestSpecification{
      name: "current_speed",
      request_frame_id: 0x7DF,
      response_frame_id: 0x7E8,
      frequency: frequency,
      mode: 0x01,
      parameter_specifications: parameters,
      can_interface: "vcan_test"
    }
  end

  describe "running OBD2 requests on a CAN bus" do
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

    defp start_request(parameters) do
      {:ok, pid} =
        Request.start_link(%{
          process_name: @request_process_name,
          request_specification: request_spec(parameters, 50)
        })

      pid
    end

    defp shutdown(pid) do
      if Process.alive?(pid) do
        Process.unlink(pid)
        ref = Process.monitor(pid)
        Process.exit(pid, :kill)
        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        after
          500 -> :ok
        end
      end
    end

    context "when an ECU answers a Mode 0x01 single-PID request" do
      it "delivers a :handle_obd2_response with the decoded parameter value" do
        pid = start_request([speed_parameter_spec()])

        try do
          :ok = Request.subscribe(self(), :test_network, "current_speed")
          FakeSocket.push_recv(<<0x41, 0x0D, 0x32>>)
          :ok = Request.enable(:test_network, "current_speed")

          assert_receive {:handle_obd2_response, %Response{request_name: "current_speed", parameters: parameters}}, 1_000
          expect(parameters["speed"].value) |> to(eq(50))
          expect(parameters["speed"].unit) |> to(eq("km/h"))
        after
          shutdown(pid)
        end
      end
    end

    context "when an ECU answers a Mode 0x01 multi-PID request" do
      it "delivers a response containing every requested parameter, decoded" do
        pid = start_request([speed_parameter_spec(), rpm_parameter_spec()])

        try do
          :ok = Request.subscribe(self(), :test_network, "current_speed")
          FakeSocket.push_recv(<<0x41, 0x0D, 0x32, 0x0C, 0x09, 0xC4>>)
          :ok = Request.enable(:test_network, "current_speed")

          assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
          expect(parameters["speed"].value) |> to(eq(50))
          expect(D.eq?(parameters["rpm"].value, D.new("625.00"))) |> to(be_true())
        after
          shutdown(pid)
        end
      end
    end

    context "the bytes sent on the bus" do
      it "encode the OBD2 mode followed by each parameter's PID id" do
        pid = start_request([speed_parameter_spec(), rpm_parameter_spec()])

        try do
          :ok = Request.subscribe(self(), :test_network, "current_speed")
          FakeSocket.push_recv(<<0x41, 0x0D, 0x32, 0x0C, 0x09, 0xC4>>)
          :ok = Request.enable(:test_network, "current_speed")

          assert_receive {:handle_obd2_response, _}, 1_000

          [first_request | _] = FakeSocket.sent()
          expect(first_request) |> to(eq(<<0x01, 0x0D, 0x0C>>))
        after
          shutdown(pid)
        end
      end
    end

    context "when the ECU returns a negative response (NRC)" do
      it "delivers a :handle_obd2_error and keeps the request process alive" do
        pid = start_request([speed_parameter_spec()])

        try do
          :ok = Request.subscribe(self(), :test_network, "current_speed")
          # 0x7F = negative response, 0x01 = the SID being rejected (Mode 0x01),
          # 0x12 = NRC subFunctionNotSupported
          FakeSocket.push_recv(<<0x7F, 0x01, 0x12>>)
          :ok = Request.enable(:test_network, "current_speed")

          assert_receive {:handle_obd2_error, {:nrc, 0x01, 0x12, :sub_function_not_supported}}, 1_000
          expect(Process.alive?(pid)) |> to(be_true())
        after
          shutdown(pid)
        end
      end

      it "recovers and decodes the next valid response from the same ECU" do
        pid = start_request([speed_parameter_spec()])

        try do
          :ok = Request.subscribe(self(), :test_network, "current_speed")
          FakeSocket.push_recv(<<0x7F, 0x01, 0x31>>)
          FakeSocket.push_recv(<<0x41, 0x0D, 0x32>>)
          :ok = Request.enable(:test_network, "current_speed")

          assert_receive {:handle_obd2_error, {:nrc, 0x01, 0x31, :request_out_of_range}}, 1_000
          assert_receive {:handle_obd2_response, %Response{parameters: %{"speed" => %{value: 50}}}}, 1_000
        after
          shutdown(pid)
        end
      end
    end

    context "when the request is disabled" do
      it "stops sending requests on the bus" do
        pid = start_request([speed_parameter_spec()])

        try do
          :ok = Request.subscribe(self(), :test_network, "current_speed")

          # Pre-load several responses; the request will only consume some
          # before we disable it.
          for _ <- 1..6, do: FakeSocket.push_recv(<<0x41, 0x0D, 0x32>>)

          :ok = Request.enable(:test_network, "current_speed")
          Process.sleep(120)

          :ok = Request.disable(:test_network, "current_speed")
          Process.sleep(30)

          count_after_disable = length(FakeSocket.sent())
          Process.sleep(150)

          expect(length(FakeSocket.sent())) |> to(eq(count_after_disable))
        after
          shutdown(pid)
        end
      end
    end
  end
end
