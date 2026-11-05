defmodule Cantastic.TickerSpec do
  use ESpec
  alias Cantastic.Ticker

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp await_tick(ref) do
    receive do
      {:tick, ^ref} -> now_ms()
    after
      500 -> :no_tick
    end
  end

  describe ".start/1" do
    it "sends the first tick one period later" do
      started_at_ms = now_ms()
      ticker = Ticker.start(30)

      expect(await_tick(ticker.ref) - started_at_ms) |> to(be_close_to(30, 5))
    end
  end

  describe ".next/1" do
    it "keeps the ticks on the grid regardless of handling time" do
      ticker = Ticker.start(30)
      grid_start_ms = ticker.next_tick_at_ms - 30

      tick_times_ms =
        Enum.map_reduce(1..5, ticker, fn _, ticker ->
          tick_at_ms = await_tick(ticker.ref)
          Process.sleep(10)
          {tick_at_ms, Ticker.next(ticker)}
        end)
        |> elem(0)

      for {tick_at_ms, tick_number} <- Enum.with_index(tick_times_ms, 1) do
        expect(tick_at_ms - grid_start_ms) |> to(be_close_to(tick_number * 30, 5))
      end
    end

    it "skips the grid slots a handler overran" do
      ticker = Ticker.start(20)
      grid_start_ms = ticker.next_tick_at_ms - 20

      await_tick(ticker.ref)
      Process.sleep(50)
      ticker = Ticker.next(ticker)

      expect(ticker.next_tick_at_ms - grid_start_ms) |> to(eq(80))
      expect(await_tick(ticker.ref) - grid_start_ms) |> to(be_close_to(80, 5))
      expect(await_tick(ticker.ref)) |> to(eq(:no_tick))
    end
  end

  describe ".cancel/1" do
    it "stops the ticks" do
      ticker = Ticker.start(20)

      expect(Ticker.cancel(ticker)) |> to(eq(nil))
      expect(await_tick(ticker.ref)) |> to(eq(:no_tick))
    end

    it "accepts nil" do
      expect(Ticker.cancel(nil)) |> to(eq(nil))
    end
  end
end
