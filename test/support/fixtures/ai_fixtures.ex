defmodule FinancialAdvisorAi.AIFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `FinancialAdvisorAi.AI` context.
  """

  alias FinancialAdvisorAi.AI
  alias FinancialAdvisorAi.AI.Conversation

  def conversation_fixture(scope_or_user_or_attrs, attrs \\ %{})

  def conversation_fixture(%{user: user} = _scope, attrs) do
    conversation_fixture(Map.put(attrs, :user, user))
  end

  def conversation_fixture(%FinancialAdvisorAi.Accounts.User{id: user_id} = _user, attrs) do
    conversation_fixture(Map.put(attrs, :user_id, user_id))
  end

  def conversation_fixture(attrs, _) do
    user_id =
      cond do
        Map.has_key?(attrs, :user_id) -> attrs[:user_id]
        Map.has_key?(attrs, :user) -> attrs[:user].id
        true -> FinancialAdvisorAi.AccountsFixtures.user_fixture().id
      end

    {:ok, conversation} =
      attrs
      |> Enum.into(%{
        title: "some title",
        user_id: user_id
      })
      |> AI.create_conversation()

    conversation
  end
end
