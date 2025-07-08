defmodule FinancialAdvisorAi.AI.HubspotNotesScheduler do
  @moduledoc """
  GenServer that schedules periodic HubSpot notes processing jobs.

  This scheduler ensures that contact notes are processed automatically
  by scheduling periodic jobs via Oban to check for contacts that need
  their notes processed and process new notes with embeddings.
  Uses a timestamp-based approach to handle notes added over time.
  """

  use GenServer
  require Logger
  alias FinancialAdvisorAi.AI.HubspotNotesJob

  # Schedule notes processing every 2 hours
  @notes_processing_interval :timer.hours(2)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl GenServer
  def init(state) do
    Logger.info("Starting HubSpot Notes Processing Scheduler")

    # Schedule the first notes processing job after a short delay
    Process.send_after(self(), :schedule_notes_processing, :timer.minutes(5))

    {:ok, state}
  end

  @impl GenServer
  def handle_info(:schedule_notes_processing, state) do
    schedule_notes_processing()
    schedule_next_processing()
    {:noreply, state}
  end

  @doc """
  Manually trigger a notes processing job for all users.
  """
  def schedule_now() do
    GenServer.cast(__MODULE__, :schedule_notes_processing)
  end

  @impl GenServer
  def handle_cast(:schedule_notes_processing, state) do
    schedule_notes_processing()
    {:noreply, state}
  end

  defp schedule_notes_processing() do
    Logger.info("Scheduling HubSpot notes processing jobs")

    case HubspotNotesJob.schedule_for_all_users() do
      {:ok, jobs} ->
        Logger.info("HubSpot notes processing jobs scheduled successfully: #{length(jobs)} jobs")

      {:error, reason} ->
        Logger.error("Failed to schedule HubSpot notes processing jobs: #{inspect(reason)}")
    end
  end

  defp schedule_next_processing() do
    Process.send_after(self(), :schedule_notes_processing, @notes_processing_interval)
  end
end
