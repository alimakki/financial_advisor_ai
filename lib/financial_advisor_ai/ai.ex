defmodule FinancialAdvisorAi.AI do
  @moduledoc """
  The AI context for managing conversations, messages, tasks, and integrations.
  """

  import Ecto.Query, warn: false
  alias FinancialAdvisorAi.Repo

  alias FinancialAdvisorAi.AI.{
    Conversation,
    Message,
    Task,
    OngoingInstruction,
    Integration,
    EmailEmbedding
  }

  # Conversations

  def list_conversations(user_id) do
    Conversation
    |> where([c], c.user_id == ^user_id)
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
  end

  def get_conversation!(id), do: Repo.get!(Conversation, id)

  def create_conversation(attrs \\ %{}) do
    %Conversation{}
    |> Conversation.changeset(attrs)
    |> Repo.insert()
  end

  def update_conversation(%Conversation{} = conversation, attrs) do
    conversation
    |> Conversation.changeset(attrs)
    |> Repo.update()
  end

  def delete_conversation(%Conversation{} = conversation) do
    Repo.delete(conversation)
  end

  # Messages

  def list_messages(conversation_id) do
    Message
    |> where([m], m.conversation_id == ^conversation_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
  end

  def create_message(attrs \\ %{}) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert()
  end

  # Tasks

  def list_tasks(user_id) do
    Task
    |> where([t], t.user_id == ^user_id)
    |> order_by([t], desc: t.inserted_at)
    |> Repo.all()
  end

  def list_pending_tasks(user_id) do
    Task
    |> where([t], t.user_id == ^user_id and t.status == "pending")
    |> order_by([t], asc: :scheduled_for)
    |> Repo.all()
  end

  def get_task!(id), do: Repo.get!(Task, id)

  def create_task(attrs \\ %{}) do
    %Task{}
    |> Task.changeset(attrs)
    |> Repo.insert()
  end

  def update_task(%Task{} = task, attrs) do
    task
    |> Task.changeset(attrs)
    |> Repo.update()
  end

  # Ongoing Instructions

  def list_active_instructions(user_id) do
    OngoingInstruction
    |> where([i], i.user_id == ^user_id and i.is_active == true)
    |> order_by([i], desc: :priority)
    |> Repo.all()
  end

  def create_instruction(attrs \\ %{}) do
    %OngoingInstruction{}
    |> OngoingInstruction.changeset(attrs)
    |> Repo.insert()
  end

  # Integrations

  def get_integration(user_id, provider) do
    Integration
    |> where([i], i.user_id == ^user_id and i.provider == ^provider)
    |> Repo.one()
  end

  def upsert_integration(attrs) do
    case get_integration(attrs.user_id, attrs.provider) do
      nil ->
        %Integration{}
        |> Integration.changeset(attrs)
        |> Repo.insert()

      existing ->
        existing
        |> Integration.changeset(attrs)
        |> Repo.update()
    end
  end

  # Email Embeddings

  def create_email_embedding(attrs \\ %{}) do
    %EmailEmbedding{}
    |> EmailEmbedding.changeset(attrs)
    |> Repo.insert()
  end

  def search_emails_by_content(user_id, query) do
    # This will be enhanced with vector search later
    EmailEmbedding
    |> where([e], e.user_id == ^user_id)
    |> where([e], ilike(e.content, ^"%#{query}%") or ilike(e.subject, ^"%#{query}%"))
    |> Repo.all()
  end
end

defmodule FinancialAdvisorAi.AI.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversations" do
    field :title, :string
    field :status, :string, default: "active"
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAdvisorAi.Accounts.User
    has_many :messages, FinancialAdvisorAi.AI.Message
    has_many :tasks, FinancialAdvisorAi.AI.Task

    timestamps(type: :utc_datetime)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:title, :status, :metadata, :user_id])
    |> validate_required([:user_id])
    |> validate_inclusion(:status, ["active", "archived", "completed"])
  end
end

defmodule FinancialAdvisorAi.AI.Message do
  use Ecto.Schema
  import Ecto.Changeset

  schema "messages" do
    field :role, :string
    field :content, :string
    field :metadata, :map, default: %{}
    field :tool_calls, :map
    field :tool_results, :map

    belongs_to :conversation, FinancialAdvisorAi.AI.Conversation

    timestamps(type: :utc_datetime)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:role, :content, :metadata, :tool_calls, :tool_results, :conversation_id])
    |> validate_required([:role, :content, :conversation_id])
    |> validate_inclusion(:role, ["user", "assistant", "system"])
  end
end

defmodule FinancialAdvisorAi.AI.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "pending"
    field :task_type, :string
    field :parameters, :map, default: %{}
    field :result, :map
    field :error_message, :string
    field :scheduled_for, :utc_datetime
    field :completed_at, :utc_datetime

    belongs_to :user, FinancialAdvisorAi.Accounts.User
    belongs_to :conversation, FinancialAdvisorAi.AI.Conversation, on_replace: :nilify

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :description,
      :status,
      :task_type,
      :parameters,
      :result,
      :error_message,
      :scheduled_for,
      :completed_at,
      :user_id,
      :conversation_id
    ])
    |> validate_required([:title, :user_id])
    |> validate_inclusion(:status, ["pending", "in_progress", "completed", "failed"])
  end
end

defmodule FinancialAdvisorAi.AI.OngoingInstruction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ongoing_instructions" do
    field :instruction, :string
    field :is_active, :boolean, default: true
    field :trigger_events, {:array, :string}, default: []
    field :priority, :integer, default: 1

    belongs_to :user, FinancialAdvisorAi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(instruction, attrs) do
    instruction
    |> cast(attrs, [:instruction, :is_active, :trigger_events, :priority, :user_id])
    |> validate_required([:instruction, :user_id])
  end
end

defmodule FinancialAdvisorAi.AI.Integration do
  use Ecto.Schema
  import Ecto.Changeset

  schema "integrations" do
    field :provider, :string
    field :access_token, :string
    field :refresh_token, :string
    field :expires_at, :utc_datetime
    field :scope, :string
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAdvisorAi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(integration, attrs) do
    integration
    |> cast(attrs, [
      :provider,
      :access_token,
      :refresh_token,
      :expires_at,
      :scope,
      :metadata,
      :user_id
    ])
    |> validate_required([:provider, :user_id])
    |> validate_inclusion(:provider, ["google", "hubspot"])
  end
end

defmodule FinancialAdvisorAi.AI.EmailEmbedding do
  use Ecto.Schema
  import Ecto.Changeset

  schema "email_embeddings" do
    field :email_id, :string
    field :subject, :string
    field :content, :string
    field :sender, :string
    field :recipient, :string
    field :embedding, :binary
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAdvisorAi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(embedding, attrs) do
    embedding
    |> cast(attrs, [
      :email_id,
      :subject,
      :content,
      :sender,
      :recipient,
      :embedding,
      :metadata,
      :user_id
    ])
    |> validate_required([:email_id, :user_id])
  end
end
