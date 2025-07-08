defmodule FinancialAdvisorAi.AI.HubspotNotesJob do
  @moduledoc """
  Oban job for processing contact notes from HubSpot.

  This job runs periodically to check for contacts that need their notes processed,
  fetches their notes from HubSpot, and processes them with vector embeddings.
  Now uses a timestamp-based approach to handle notes that are added over time.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  require Logger
  alias FinancialAdvisorAi.Integrations.HubspotService

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    Logger.info("Processing HubSpot notes for user #{user_id}")

    case HubspotService.process_contact_notes(user_id) do
      {:ok, %{processed_count: count, results: results}} ->
        # Log any individual contact errors
        errors =
          Enum.filter(results, fn {_contact_id, result} ->
            case result do
              {:error, _} -> true
              _ -> false
            end
          end)

        if length(errors) > 0 do
          Logger.warning(
            "Some contacts had errors during processing for user #{user_id}: #{inspect(errors)}"
          )
        end

        Logger.info("Successfully processed notes for #{count} contacts (user #{user_id})")
        :ok
    end
  end

  @doc """
  Schedules a job to process notes for a specific user.
  """
  def schedule_for_user(user_id) do
    %{"user_id" => user_id}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Schedules jobs to process notes for all users with HubSpot integrations.
  """
  def schedule_for_all_users do
    case FinancialAdvisorAi.AI.list_users_with_integrations("hubspot") do
      users when is_list(users) ->
        jobs =
          Enum.map(users, fn user ->
            schedule_for_user(user.id)
          end)

        # Return the successfully created jobs
        successful_jobs =
          Enum.filter(jobs, fn
            {:ok, _job} -> true
            _ -> false
          end)

        {:ok, successful_jobs}

      error ->
        Logger.error("Failed to get users with HubSpot integrations: #{inspect(error)}")
        {:error, "Failed to get users with HubSpot integrations"}
    end
  end
end
