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
    EmailEmbedding,
    ContactEmbedding,
    ContactNote
  }

  alias FinancialAdvisorAi.Integrations.TokenRefreshService

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

  def get_integration(user_id, provider) when is_nil(user_id) or is_nil(provider), do: nil

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

  def delete_integration(%Integration{} = integration) do
    Repo.delete(integration)
  end

  @doc """
  Gets an integration with automatic token refresh if needed.

  This function will automatically refresh the access token if it's expired
  or close to expiry, returning the updated integration.
  """
  def get_integration_with_refresh(user_id, provider) do
    case get_integration(user_id, provider) do
      nil ->
        nil

      integration ->
        case TokenRefreshService.refresh_if_needed(integration) do
          {:ok, updated_integration} -> updated_integration
          {:error, _reason} -> integration
        end
    end
  end

  @doc """
  Lists all integrations that need token refresh (expired or expiring soon).
  """
  def list_integrations_needing_refresh() do
    # Get integrations that expire within the next hour
    one_hour_from_now = DateTime.utc_now() |> DateTime.add(60 * 60, :second)

    Integration
    |> where([i], not is_nil(i.expires_at) and i.expires_at <= ^one_hour_from_now)
    |> Repo.all()
    |> Enum.filter(&Integration.token_expires_soon?/1)
  end

  @doc """
  Lists all integrations for a specific user that need token refresh.
  """
  def list_user_integrations_needing_refresh(user_id) do
    Integration
    |> where([i], i.user_id == ^user_id and not is_nil(i.expires_at))
    |> Repo.all()
    |> Enum.filter(&Integration.token_expires_soon?/1)
  end

  @doc """
  Refreshes tokens for all integrations that need it.
  Returns a summary of refresh results.
  """
  def refresh_all_expiring_tokens() do
    integrations = list_integrations_needing_refresh()

    results =
      Enum.map(integrations, fn integration ->
        case TokenRefreshService.refresh_if_needed(integration) do
          {:ok, _updated} -> {:ok, integration.provider, integration.user_id}
          {:error, reason} -> {:error, integration.provider, integration.user_id, reason}
        end
      end)

    success_count = Enum.count(results, fn {status, _, _} -> status == :ok end)
    error_count = Enum.count(results, fn {status, _, _, _} -> status == :error end)

    %{
      total: length(integrations),
      success: success_count,
      errors: error_count,
      results: results
    }
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

  # Contact Embeddings

  def create_contact_embedding(attrs \\ %{}) do
    %ContactEmbedding{}
    |> ContactEmbedding.changeset(attrs)
    |> Repo.insert()
  end

  def get_contact_embedding_by_contact_id(user_id, contact_id) do
    ContactEmbedding
    |> where([c], c.user_id == ^user_id and c.contact_id == ^contact_id)
    |> Repo.one()
  end

  def update_contact_embedding(%ContactEmbedding{} = contact_embedding, attrs) do
    contact_embedding
    |> ContactEmbedding.changeset(attrs)
    |> Repo.update()
  end

  def search_contacts_by_content(user_id, query) do
    ContactEmbedding
    |> where([c], c.user_id == ^user_id)
    |> where(
      [c],
      ilike(c.content, ^"%#{query}%") or
        ilike(c.firstname, ^"%#{query}%") or
        ilike(c.lastname, ^"%#{query}%") or
        ilike(c.email, ^"%#{query}%") or
        ilike(c.company, ^"%#{query}%")
    )
    |> Repo.all()
  end

  # Contact Notes

  def create_contact_note(attrs \\ %{}) do
    %ContactNote{}
    |> ContactNote.changeset(attrs)
    |> Repo.insert()
  end

  def get_contact_note!(id), do: Repo.get!(ContactNote, id)

  def get_contact_notes_by_contact_id(user_id, contact_id) do
    contact_embedding = get_contact_embedding_by_contact_id(user_id, contact_id)

    if contact_embedding do
      ContactNote
      |> where([n], n.user_id == ^user_id and n.contact_embedding_id == ^contact_embedding.id)
      |> Repo.all()
    else
      []
    end
  end

  def get_contact_note_by_hubspot_id(user_id, hubspot_note_id) do
    ContactNote
    |> where([n], n.user_id == ^user_id and n.hubspot_note_id == ^hubspot_note_id)
    |> Repo.one()
  end

  def update_contact_note(%ContactNote{} = contact_note, attrs) do
    contact_note
    |> ContactNote.changeset(attrs)
    |> Repo.update()
  end

  def delete_contact_note(%ContactNote{} = contact_note) do
    Repo.delete(contact_note)
  end

  def search_contact_notes_by_content(user_id, query) do
    ContactNote
    |> where([n], n.user_id == ^user_id)
    |> where([n], ilike(n.content, ^"%#{query}%"))
    |> Repo.all()
  end
end
