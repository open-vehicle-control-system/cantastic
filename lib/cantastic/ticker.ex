defmodule Cantastic.Ticker do
  @moduledoc """
    `Cantastic.Ticker` sends `{:tick, ref}` to the calling process once per period, on a grid of monotonic deadlines started by `start/1`.

    The process handles a tick, then calls `next/1` to arm the following one, so at most one tick is ever pending. When handling a tick overruns the period, the overrun grid slots are skipped rather than queued, and the period does not drift with handling time.

    A tick already in the mailbox when `cancel/1` runs still arrives: match `ref` against the running ticker to ignore it.

    ```elixir
    def handle_info({:tick, ref}, %{ticker: %Ticker{ref: ref}} = state) do
      state = send_frame(state)
      {:noreply, %{state | ticker: Ticker.next(state.ticker)}}
    end

    def handle_info({:tick, _stale_ref}, state), do: {:noreply, state}
    ```
  """

  @enforce_keys [:ref, :period_ms, :next_tick_at_ms]
  defstruct [:ref, :period_ms, :next_tick_at_ms, :timer]

  @doc """
  Start a ticker whose first tick arrives `period_ms` milliseconds from now.
  """
  def start(period_ms) do
    schedule(%__MODULE__{
      ref: make_ref(),
      period_ms: period_ms,
      next_tick_at_ms: System.monotonic_time(:millisecond)
    })
  end

  @doc """
  Arm the next tick, on the first grid slot still in the future. Call it from the process that started the ticker.
  """
  def next(%__MODULE__{} = ticker), do: schedule(ticker)

  @doc """
  Cancel the pending tick. Accepts `nil` and always returns `nil`.
  """
  def cancel(nil), do: nil

  def cancel(%__MODULE__{timer: timer}) do
    Process.cancel_timer(timer)
    nil
  end

  defp schedule(%__MODULE__{period_ms: period_ms} = ticker) do
    now_ms = System.monotonic_time(:millisecond)
    next_tick_at_ms = ticker.next_tick_at_ms + period_ms

    next_tick_at_ms =
      if next_tick_at_ms > now_ms,
        do: next_tick_at_ms,
        else: next_tick_at_ms + (div(now_ms - next_tick_at_ms, period_ms) + 1) * period_ms

    timer = Process.send_after(self(), {:tick, ticker.ref}, next_tick_at_ms, abs: true)
    %{ticker | next_tick_at_ms: next_tick_at_ms, timer: timer}
  end
end
