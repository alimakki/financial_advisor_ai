defmodule FinancialAdvisorAi.AI.HubspotPollJob do
  @moduledoc """
  HubSpot poll job for the Financial Advisor AI web application.
  Polls for new or updated contacts and notes in HubSpot.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias FinancialAdvisorAi.Integrations.HubspotService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    HubspotService.poll_and_import_contacts_and_notes(user_id)
    :ok
  end
end
