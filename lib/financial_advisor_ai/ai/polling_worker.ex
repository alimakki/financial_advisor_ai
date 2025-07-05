defmodule FinancialAdvisorAi.AI.PollingWorker do
  @moduledoc """
  Periodically polls Gmail, Google Calendar, and Hubspot for new events for all users.
  Sends new events to EventProcessor for processing.
  """
  use GenServer

  alias FinancialAdvisorAi.Accounts

  alias FinancialAdvisorAi.Integrations.{
    GmailService,
    CalendarService,
    HubspotService,
    EventProcessor
  }

  @poll_interval :timer.minutes(5)

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
    for user <- Accounts.list_users() do
      poll_user(user.id)
    end
  end

  @doc """
  Polls a single user for new events in all integrations.
  """
  def poll_user(user_id) do
    with {:ok, gmail_events} <- GmailService.poll_new_messages(user_id),
         {:ok, calendar_events} <- CalendarService.poll_new_events(user_id),
         {:ok, hubspot_events} <- HubspotService.poll_new_events(user_id) do
      Enum.each(gmail_events, &EventProcessor.process_event("gmail", &1))
      Enum.each(calendar_events, &EventProcessor.process_event("calendar", &1))
      Enum.each(hubspot_events, &EventProcessor.process_event("hubspot", &1))
    end
  end
end
