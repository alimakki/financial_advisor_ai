defmodule FinancialAdvisorAi.Repo.Migrations.CreateCoreAiSchemas do
  use Ecto.Migration

  def change do
    # Conversations table
    create table(:conversations) do
      add :title, :string
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :status, :string, default: "active"
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:conversations, [:user_id])
    create index(:conversations, [:status])

    # Messages table
    create table(:messages) do
      add :conversation_id, references(:conversations, on_delete: :delete_all), null: false
      # "user", "assistant", "system"
      add :role, :string, null: false
      add :content, :text, null: false
      add :metadata, :map, default: %{}
      # For storing tool call information
      add :tool_calls, :map
      # For storing tool call results
      add :tool_results, :map

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:conversation_id])
    create index(:messages, [:role])

    # Tasks table for persistent task management
    create table(:tasks) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :conversation_id, references(:conversations, on_delete: :delete_all)
      add :title, :string, null: false
      add :description, :text
      # pending, in_progress, completed, failed
      add :status, :string, default: "pending"
      # email, calendar, hubspot, etc.
      add :task_type, :string
      add :parameters, :map, default: %{}
      add :result, :map
      add :error_message, :text
      add :scheduled_for, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:tasks, [:user_id])
    create index(:tasks, [:status])
    create index(:tasks, [:task_type])
    create index(:tasks, [:scheduled_for])

    # Ongoing instructions table
    create table(:ongoing_instructions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :instruction, :text, null: false
      add :is_active, :boolean, default: true
      # ["email_received", "calendar_updated", etc.]
      add :trigger_events, {:array, :string}, default: []
      add :priority, :integer, default: 1

      timestamps(type: :utc_datetime)
    end

    create index(:ongoing_instructions, [:user_id])
    create index(:ongoing_instructions, [:is_active])

    # Integrations table for storing OAuth tokens
    create table(:integrations) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # "google", "hubspot"
      add :provider, :string, null: false
      add :access_token, :text
      add :refresh_token, :text
      add :expires_at, :utc_datetime
      add :scope, :string
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:integrations, [:user_id])
    create index(:integrations, [:provider])
    create unique_index(:integrations, [:user_id, :provider])

    # Email embeddings for RAG
    create table(:email_embeddings) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # Gmail message ID
      add :email_id, :string, null: false
      add :subject, :string
      add :content, :text
      add :sender, :string
      add :recipient, :string
      # Will store vector embeddings
      add :embedding, :binary
      add :metadata, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:email_embeddings, [:user_id])
    create index(:email_embeddings, [:email_id])
    create index(:email_embeddings, [:sender])
  end
end
