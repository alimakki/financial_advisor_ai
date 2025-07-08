#!/usr/bin/env elixir

# HubSpot Notes Worker Test Script
# This script demonstrates how to use the new periodic notes processing worker

# Run this script with: elixir test_notes_worker.exs

defmodule HubspotNotesWorkerTest do
  @moduledoc """
  Test script for the HubSpot notes processing worker system.
  """

  alias FinancialAdvisorAi.AI.{HubspotNotesJob, HubspotNotesScheduler}
  alias FinancialAdvisorAi.AI

  def run_tests() do
    IO.puts("🔧 HubSpot Notes Worker Testing")
    IO.puts("=" <> String.duplicate("=", 50))

    # Test 1: Check for unprocessed contacts
    test_check_unprocessed_contacts()

    # Test 2: Schedule a job for a specific user
    test_schedule_user_job()

    # Test 3: Schedule jobs for all users
    test_schedule_all_users()

    # Test 4: Manually trigger the scheduler
    test_manual_scheduler_trigger()

    # Test 5: Check job status
    test_check_job_status()

    IO.puts("\n✅ All tests completed!")
  end

  defp test_check_unprocessed_contacts() do
    IO.puts("\n📋 Test 1: Checking for unprocessed contacts")

    # Replace with actual user ID
    user_id = "your_user_id_here"

    unprocessed = AI.list_contacts_with_unprocessed_notes(user_id)
    IO.puts("Found #{length(unprocessed)} contacts with unprocessed notes")

    if length(unprocessed) > 0 do
      IO.puts("Sample unprocessed contacts:")

      unprocessed
      |> Enum.take(3)
      |> Enum.each(fn contact ->
        name = [contact.firstname, contact.lastname] |> Enum.filter(& &1) |> Enum.join(" ")
        IO.puts("  • #{name} (#{contact.email})")
      end)
    end
  end

  defp test_schedule_user_job() do
    IO.puts("\n⏰ Test 2: Scheduling job for specific user")

    user_id = "your_user_id_here"

    case HubspotNotesJob.schedule_for_user(user_id) do
      {:ok, job} ->
        IO.puts("✅ Job scheduled successfully for user #{user_id}")
        IO.puts("Job ID: #{job.id}")
        IO.puts("Queue: #{job.queue}")
        IO.puts("Scheduled for: #{job.scheduled_at}")

      {:error, reason} ->
        IO.puts("❌ Failed to schedule job: #{inspect(reason)}")
    end
  end

  defp test_schedule_all_users() do
    IO.puts("\n👥 Test 3: Scheduling jobs for all users")

    case HubspotNotesJob.schedule_for_all_users() do
      {:ok, jobs} ->
        IO.puts("✅ Scheduled #{length(jobs)} jobs for all users with HubSpot integrations")

        if length(jobs) > 0 do
          IO.puts("Sample jobs:")

          jobs
          |> Enum.take(3)
          |> Enum.each(fn job ->
            user_id = job.args["user_id"]
            IO.puts("  • Job #{job.id} for user #{user_id}")
          end)
        end

      {:error, reason} ->
        IO.puts("❌ Failed to schedule jobs: #{inspect(reason)}")
    end
  end

  defp test_manual_scheduler_trigger() do
    IO.puts("\n🚀 Test 4: Manually triggering scheduler")

    # This would only work if the application is running
    try do
      HubspotNotesScheduler.schedule_now()
      IO.puts("✅ Scheduler triggered successfully")
    rescue
      e ->
        IO.puts("⚠️  Scheduler not running (expected in test): #{inspect(e)}")
    end
  end

  defp test_check_job_status() do
    IO.puts("\n📊 Test 5: Checking job status")

    # Query recent jobs from Oban
    try do
      recent_jobs =
        Oban.Job
        |> Ecto.Query.where([j], j.worker == "FinancialAdvisorAi.AI.HubspotNotesJob")
        |> Ecto.Query.order_by([j], desc: j.inserted_at)
        |> Ecto.Query.limit(5)
        |> FinancialAdvisorAi.Repo.all()

      IO.puts("Recent HubSpot notes jobs:")

      if length(recent_jobs) > 0 do
        Enum.each(recent_jobs, fn job ->
          IO.puts("  • Job #{job.id}: #{job.state} (#{job.worker})")
          IO.puts("    User: #{job.args["user_id"]}")
          IO.puts("    Created: #{job.inserted_at}")
          IO.puts("    Attempts: #{job.attempt}/#{job.max_attempts}")
        end)
      else
        IO.puts("  No recent jobs found")
      end
    rescue
      e ->
        IO.puts("⚠️  Could not query jobs (database not available): #{inspect(e)}")
    end
  end
end

# Show usage instructions
IO.puts("""
🎯 HubSpot Notes Worker Test Script

This script tests the new periodic notes processing worker system.

Features tested:
- Checking for unprocessed contacts
- Scheduling jobs for specific users
- Scheduling jobs for all users
- Manual scheduler triggers
- Job status monitoring

To run the tests:
1. Replace 'your_user_id_here' with an actual user ID
2. Ensure your application is running (iex -S mix)
3. Run: elixir test_notes_worker.exs

Or load in IEx:
iex> import_file("test_notes_worker.exs")
iex> HubspotNotesWorkerTest.run_tests()
""")

# Only run if called directly
if System.argv() |> length() == 0 do
  try do
    HubspotNotesWorkerTest.run_tests()
  rescue
    e ->
      IO.puts("❌ Error running tests: #{inspect(e)}")
      IO.puts("Make sure to run this in the context of your application (iex -S mix)")
  end
end
