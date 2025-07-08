defmodule FinancialAdvisorAi.AI.TokenRefreshScheduler do
  @moduledoc """
  GenServer that schedules periodic token refresh jobs.

  This scheduler ensures that OAuth tokens are refreshed automatically
  before they expire by scheduling periodic jobs via Oban.
  """

  use GenServer
  require Logger
  alias FinancialAdvisorAi.AI.TokenRefreshJob

  # Schedule token refresh every 30 minutes
  @refresh_interval :timer.minutes(30)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl GenServer
  def init(state) do
    Logger.info("Starting Token Refresh Scheduler")

    # Schedule the first token refresh job immediately
    schedule_token_refresh()

    # Schedule periodic checks
    schedule_next_refresh()

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:schedule_refresh, state) do
    schedule_token_refresh()
    schedule_next_refresh()
    {:noreply, state}
  end

  defp schedule_token_refresh() do
    Logger.info("Scheduling token refresh job")

    case TokenRefreshJob.schedule_refresh_all_tokens() do
      {:ok, _job} ->
        Logger.info("Token refresh job scheduled successfully")

      {:error, reason} ->
        Logger.error("Failed to schedule token refresh job: #{inspect(reason)}")
    end
  end

  defp schedule_next_refresh() do
    Process.send_after(self(), :schedule_refresh, @refresh_interval)
  end
end
