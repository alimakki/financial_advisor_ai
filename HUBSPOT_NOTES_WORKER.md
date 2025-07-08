# HubSpot Notes Worker System

This document describes the periodic worker system for processing HubSpot contact notes with vector embeddings.

## Overview

The HubSpot Notes Worker system automatically processes notes for contacts that haven't had their notes imported yet. It runs periodically to:

1. Find contacts with `notes_processed: false`
2. Fetch their notes from HubSpot API
3. Generate vector embeddings for semantic search
4. Store notes in the `contact_notes` table
5. Mark contacts as `notes_processed: true`

## Components

### 1. HubspotNotesJob (`lib/financial_advisor_ai/ai/hubspot_notes_job.ex`)

An Oban worker that processes unprocessed contact notes for a specific user.

**Features:**
- Runs as background job with 3 retry attempts
- Processes all unprocessed contacts for a user
- Logs processing results
- Graceful error handling

**Usage:**
```elixir
# Schedule job for specific user
HubspotNotesJob.schedule_for_user("user_id")

# Schedule jobs for all users with HubSpot integrations
HubspotNotesJob.schedule_for_all_users()
```

### 2. HubspotNotesScheduler (`lib/financial_advisor_ai/ai/hubspot_notes_scheduler.ex`)

A GenServer that schedules periodic notes processing jobs.

**Features:**
- Runs every 2 hours by default
- Schedules jobs for all users with HubSpot integrations
- Manual trigger capability
- Automatic startup with application

**Usage:**
```elixir
# Manually trigger scheduling
HubspotNotesScheduler.schedule_now()
```

### 3. PollingWorker Integration

The existing `PollingWorker` now also schedules `HubspotNotesJob` alongside regular HubSpot polling.

**Frequency:**
- Every 1 minute (same as other polling)
- Only for users with HubSpot integrations

## Configuration

### Scheduling Intervals

**HubspotNotesScheduler:**
- Default: Every 2 hours
- Configurable via `@notes_processing_interval`

**PollingWorker:**
- Default: Every 1 minute
- Configurable via `@poll_interval`

### Job Settings

**Queue:** `:default`
**Max Attempts:** 3
**Worker:** `FinancialAdvisorAi.AI.HubspotNotesJob`

## Usage Examples

### Check for Unprocessed Contacts

```elixir
# List contacts that need notes processing
unprocessed = FinancialAdvisorAi.AI.list_contacts_with_unprocessed_notes(user_id)

# Process manually
FinancialAdvisorAi.AI.process_all_unprocessed_contact_notes(user_id)
```

### Schedule Jobs

```elixir
# Schedule for specific user
{:ok, job} = HubspotNotesJob.schedule_for_user("user_123")

# Schedule for all users
{:ok, jobs} = HubspotNotesJob.schedule_for_all_users()

# Manual scheduler trigger
HubspotNotesScheduler.schedule_now()
```

### Monitor Job Status

```elixir
# Query recent jobs
recent_jobs = 
  Oban.Job
  |> Ecto.Query.where([j], j.worker == "FinancialAdvisorAi.AI.HubspotNotesJob")
  |> Ecto.Query.order_by([j], desc: j.inserted_at)
  |> Ecto.Query.limit(10)
  |> FinancialAdvisorAi.Repo.all()

# Check job status
Enum.each(recent_jobs, fn job ->
  IO.puts("Job #{job.id}: #{job.state} (#{job.attempt}/#{job.max_attempts} attempts)")
end)
```

## Interactive Tools

### IEx Console

```elixir
# Start IEx
iex -S mix

# Load interactive processor
import_file("process_notes_iex.exs")

# Use interactive tools
HubspotNotesProcessor.run_interactive("user_id")
```

### Test Script

```bash
# Run test script
elixir test_notes_worker.exs

# Or load in IEx
iex> import_file("test_notes_worker.exs")
iex> HubspotNotesWorkerTest.run_tests()
```

## Database Schema

### Contact Embeddings Table

```sql
contact_embeddings (
  id: binary_id,
  user_id: binary_id,
  contact_id: string,
  notes_processed: boolean DEFAULT false,
  -- other fields...
)
```

### Contact Notes Table

```sql
contact_notes (
  id: binary_id,
  user_id: binary_id,
  contact_embedding_id: binary_id,
  hubspot_note_id: string,
  content: text,
  embedding: vector(1536),
  metadata: jsonb,
  -- timestamps...
)
```

## Error Handling

### Job Failures

- **Max Attempts:** 3 retries
- **Retry Delay:** Exponential backoff
- **Logging:** Error details logged with context

### API Errors

- **Token Refresh:** Automatic token refresh
- **Rate Limits:** Handled by Oban's built-in retry logic
- **Network Issues:** Retry with exponential backoff

### Data Validation

- **Duplicate Prevention:** Uses `hubspot_note_id` uniqueness
- **Embedding Generation:** Fallback to text storage if embedding fails
- **Content Validation:** Skips empty or invalid notes

## Monitoring

### Log Messages

```
[info] Processing unprocessed HubSpot notes for user user_123
[info] Successfully processed notes for 5 contacts (user user_123)
[info] Scheduling 3 HubSpot notes processing jobs
```

### Metrics

Track these metrics for monitoring:
- Number of unprocessed contacts per user
- Job success/failure rates
- Processing time per user
- Embedding generation success rate

## Performance

### Batch Processing

- Processes all unprocessed contacts per user in one job
- Efficient database queries with proper indexing
- Minimal API calls to HubSpot

### Resource Usage

- **Memory:** Moderate (vector embeddings storage)
- **CPU:** Low to moderate (embedding generation)
- **Network:** Depends on number of notes per contact

## Deployment

### Application Startup

The scheduler starts automatically with the application:

```elixir
# lib/financial_advisor_ai/application.ex
children = [
  # ... other children
  FinancialAdvisorAi.AI.HubspotNotesScheduler
]
```

### Environment Variables

No additional environment variables required. Uses existing:
- `HUBSPOT_CLIENT_ID`
- `HUBSPOT_CLIENT_SECRET`
- `OPENAI_API_KEY`

## Troubleshooting

### Common Issues

1. **No jobs being scheduled:**
   - Check if users have HubSpot integrations
   - Verify scheduler is running
   - Check Oban configuration

2. **Jobs failing:**
   - Check HubSpot API credentials
   - Verify token refresh is working
   - Check network connectivity

3. **No unprocessed contacts:**
   - Verify contacts were imported correctly
   - Check `notes_processed` field values
   - Ensure contacts have notes in HubSpot

### Debug Commands

```elixir
# Check scheduler status
Process.whereis(FinancialAdvisorAi.AI.HubspotNotesScheduler)

# Check recent jobs
Oban.Job |> Ecto.Query.order_by(desc: :inserted_at) |> Ecto.Query.limit(5) |> Repo.all()

# Check unprocessed contacts
FinancialAdvisorAi.AI.list_contacts_with_unprocessed_notes(user_id)
```

## Future Enhancements

1. **Incremental Processing:** Process only recently updated notes
2. **Priority Queues:** Prioritize important contacts
3. **Batch Size Control:** Configurable batch sizes for large datasets
4. **Health Checks:** Endpoint for monitoring worker health
5. **Metrics Dashboard:** Real-time processing metrics 