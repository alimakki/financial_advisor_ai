defmodule FinancialAdvisorAi.AI.PollingWorker do
  @moduledoc """
  Periodically polls Gmail, Google Calendar, and Hubspot for new events for all users.
  Sends new events to EventProcessor for processing.
  """
  use GenServer

  alias FinancialAdvisorAi.{Accounts, Repo}

  require Logger

  alias FinancialAdvisorAi.Integrations.{
    GmailService,
    CalendarService,
    HubspotService,
    EventProcessor
  }

  @poll_interval :timer.minutes(1)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_poll()
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    poll_all_users()
    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval)
  end

  @doc """
  Polls all users for new events in Gmail, Calendar, and Hubspot.
  """
  def poll_all_users do
    Repo.checkout(fn ->
      users = Accounts.list_users()
      Logger.info("Polling all users for new events, count: #{length(users)}")

      for user <- users do
        # Only enqueue for users with a Google integration
        case FinancialAdvisorAi.AI.get_integration(user.id, "google") do
          nil ->
            :noop

          _integration ->
            Oban.insert(FinancialAdvisorAi.AI.GmailPollJob.new(%{"user_id" => user.id}))
        end
      end
    end)
  end

  @doc """
  Polls a single user for new events in all integrations.
  """
  def poll_user(user_id) do
    with {:ok, gmail_events} <- GmailService.poll_and_import_new_messages(user_id),
         {:ok, calendar_events} <- CalendarService.poll_new_events(user_id),
         {:ok, hubspot_events} <- HubspotService.poll_new_events(user_id) do
      # Process events for the specific user
      Enum.each(gmail_events, fn event ->
        EventProcessor.process_event("gmail", event)
      end)

      Enum.each(calendar_events, fn event ->
        EventProcessor.process_event("calendar", event)
      end)

      Enum.each(hubspot_events, fn event ->
        EventProcessor.process_event("hubspot", event)
      end)
    end
  end
end
