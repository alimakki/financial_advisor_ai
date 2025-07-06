defmodule FinancialAdvisorAi.AI.GmailPollJob do
  use Oban.Worker, queue: :default, max_attempts: 3

  alias FinancialAdvisorAi.Integrations.GmailService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    # GmailService.poll_and_import_new_messages(user_id)
    :ok
  end
end
