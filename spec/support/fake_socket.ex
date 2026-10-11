defmodule Cantastic.FakeSocket do
  @moduledoc false
  # In-memory stand-in for a SocketCAN socket, used by spec suites to drive
  # Cantastic.Receiver / Emitter / OBD2.Request without touching the kernel.
  #
  # The pattern is:
  #   * specs stub `Cantastic.Socket` via `allow ... to accept(...)` so that
  #     `bind_raw/1`, `bind_isotp/4`, `send/2` and `receive_message/1,2` route
  #     through this agent;
  #   * `push_recv/1` lets the spec inject a frame to be returned by the
  #     next `receive_message` call (the stub blocks until one is available,
  #     or until `receive_message/1`'s `timeout_ms` elapses);
  #   * `sent/0` lets the spec inspect what `send/2` was asked to write.

  use Agent

  @poll_interval_ms 5

  def start_link(_ \\ nil) do
    Agent.start_link(fn -> initial() end, name: __MODULE__)
  end

  def reset do
    Agent.update(__MODULE__, fn _ -> initial() end)
  end

  def push_recv(raw) do
    Agent.update(__MODULE__, fn state ->
      %{state | recv_queue: state.recv_queue ++ [raw]}
    end)
  end

  def pop_recv(timeout_ms \\ :infinity) do
    deadline_ms =
      if timeout_ms == :infinity,
        do: :infinity,
        else: System.monotonic_time(:millisecond) + timeout_ms

    pop_recv_until(deadline_ms)
  end

  defp pop_recv_until(deadline_ms) do
    case Agent.get_and_update(__MODULE__, fn state ->
           case state.recv_queue do
             [] -> {:empty, state}
             [head | tail] -> {head, %{state | recv_queue: tail}}
           end
         end) do
      :empty ->
        if deadline_ms != :infinity and System.monotonic_time(:millisecond) >= deadline_ms do
          :timeout
        else
          Process.sleep(@poll_interval_ms)
          pop_recv_until(deadline_ms)
        end

      raw ->
        raw
    end
  end

  def receive_message(timeout_ms) do
    case pop_recv(timeout_ms) do
      :timeout -> {:error, :timeout}
      raw -> {:ok, %Cantastic.SocketMessage{raw: raw, reception_timestamp: 0}}
    end
  end

  def record_send(raw) do
    Agent.update(__MODULE__, fn state -> %{state | sent: state.sent ++ [raw]} end)
  end

  def sent, do: Agent.get(__MODULE__, fn state -> state.sent end)

  defp initial, do: %{recv_queue: [], sent: []}
end
