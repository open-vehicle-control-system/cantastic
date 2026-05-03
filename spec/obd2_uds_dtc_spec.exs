defmodule Cantastic.OBD2.UdsDtcSpec do
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

  describe "clearing DTCs (Mode 0x14)" do
    context "with the default group_of_dtc (clear all)" do
      it "sends 0x14 followed by 0xFFFFFF and ECU acknowledges" do
        pid = start("uds_clear", 0x14)

        try do
          :ok = Request.subscribe(self(), :test_network, "uds_clear")
          FakeSocket.push_recv(<<0x54>>)
          :ok = Request.enable(:test_network, "uds_clear")

          assert_receive {:handle_obd2_response, %Response{mode: 0x54, parameters: %{}}}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x14, 0xFF, 0xFF, 0xFF>>))
        after
          shutdown(pid)
        end
      end
    end

    context "with an explicit group_of_dtc" do
      it "encodes the chosen 3-byte group" do
        pid = start("uds_clear", 0x14, %{group_of_dtc: 0xFFFF33})

        try do
          :ok = Request.subscribe(self(), :test_network, "uds_clear")
          FakeSocket.push_recv(<<0x54>>)
          :ok = Request.enable(:test_network, "uds_clear")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x14, 0xFF, 0xFF, 0x33>>))
        after
          shutdown(pid)
        end
      end
    end
  end

  describe "reading DTC info (Mode 0x19, sub-function 0x02)" do
    context "when the ECU reports no DTCs" do
      it "delivers a response with an empty record list" do
        pid = start("uds_read_dtcs", 0x19)

        try do
          :ok = Request.subscribe(self(), :test_network, "uds_read_dtcs")
          # SID 0x59, sub 0x02, availability_mask 0xFF, no records
          FakeSocket.push_recv(<<0x59, 0x02, 0xFF>>)
          :ok = Request.enable(:test_network, "uds_read_dtcs")

          assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
          expect(parameters["dtc_records"].value) |> to(eq([]))
        after
          shutdown(pid)
        end
      end
    end

    context "when the ECU reports several DTC records with status bytes" do
      it "decodes each as %{code, fault_type, status}" do
        pid = start("uds_read_dtcs", 0x19)

        try do
          :ok = Request.subscribe(self(), :test_network, "uds_read_dtcs")
          # SID 0x59, sub 0x02, mask 0xFF
          # Record 1: P0301 fault_type 0x00, status 0x09
          # Record 2: U0100 fault_type 0x88, status 0x29
          FakeSocket.push_recv(
            <<0x59, 0x02, 0xFF, 0x03, 0x01, 0x00, 0x09, 0xC1, 0x00, 0x88, 0x29>>
          )
          :ok = Request.enable(:test_network, "uds_read_dtcs")

          assert_receive {:handle_obd2_response, %Response{parameters: parameters}}, 1_000
          expect(parameters["dtc_records"].value)
          |> to(
            eq([
              %{code: "P0301", fault_type: 0x00, status: 0x09},
              %{code: "U0100", fault_type: 0x88, status: 0x29}
            ])
          )
        after
          shutdown(pid)
        end
      end
    end

    context "the bytes sent on the bus" do
      it "default to <<0x19, 0x02, 0xFF>> (sub 0x02, status mask 0xFF)" do
        pid = start("uds_read_dtcs", 0x19)

        try do
          :ok = Request.subscribe(self(), :test_network, "uds_read_dtcs")
          FakeSocket.push_recv(<<0x59, 0x02, 0xFF>>)
          :ok = Request.enable(:test_network, "uds_read_dtcs")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x19, 0x02, 0xFF>>))
        after
          shutdown(pid)
        end
      end

      it "honour explicit sub_function and status_mask options" do
        pid = start("uds_read_dtcs", 0x19, %{sub_function: 0x02, status_mask: 0x09})

        try do
          :ok = Request.subscribe(self(), :test_network, "uds_read_dtcs")
          FakeSocket.push_recv(<<0x59, 0x02, 0xFF>>)
          :ok = Request.enable(:test_network, "uds_read_dtcs")

          assert_receive {:handle_obd2_response, _}, 1_000
          [first | _] = FakeSocket.sent()
          expect(first) |> to(eq(<<0x19, 0x02, 0x09>>))
        after
          shutdown(pid)
        end
      end
    end
  end
end
