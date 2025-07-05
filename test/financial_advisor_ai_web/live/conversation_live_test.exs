defmodule FinancialAdvisorAiWeb.ConversationLiveTest do
  use FinancialAdvisorAiWeb.ConnCase

  import Phoenix.LiveViewTest
  import FinancialAdvisorAi.AIFixtures

  @create_attrs %{title: "some title"}
  @update_attrs %{title: "some updated title"}
  @invalid_attrs %{title: nil}

  setup :register_and_log_in_user

  defp create_conversation(%{scope: scope}) do
    conversation = conversation_fixture(scope)

    %{conversation: conversation}
  end

  describe "Index" do
    setup [:create_conversation]

    test "lists all conversations", %{conn: conn, conversation: conversation} do
      {:ok, _index_live, html} = live(conn, ~p"/conversations")

      assert html =~ "Listing Conversations"
      assert html =~ conversation.title
    end

    test "saves new conversation", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/conversations")

      assert {:ok, form_live, _} =
               index_live
               |> element("a", "New Conversation")
               |> render_click()
               |> follow_redirect(conn, ~p"/conversations/new")

      assert render(form_live) =~ "New Conversation"

      assert form_live
             |> form("#conversation-form", conversation: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#conversation-form", conversation: @create_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/conversations")

      html = render(index_live)
      assert html =~ "Conversation created successfully"
      assert html =~ "some title"
    end

    test "updates conversation in listing", %{conn: conn, conversation: conversation} do
      {:ok, index_live, _html} = live(conn, ~p"/conversations")

      assert {:ok, form_live, _html} =
               index_live
               |> element("#conversations-#{conversation.id} a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/conversations/#{conversation}/edit")

      assert render(form_live) =~ "Edit Conversation"

      assert form_live
             |> form("#conversation-form", conversation: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, index_live, _html} =
               form_live
               |> form("#conversation-form", conversation: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/conversations")

      html = render(index_live)
      assert html =~ "Conversation updated successfully"
      assert html =~ "some updated title"
    end

    test "deletes conversation in listing", %{conn: conn, conversation: conversation} do
      {:ok, index_live, _html} = live(conn, ~p"/conversations")

      assert index_live
             |> element("#conversations-#{conversation.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#conversations-#{conversation.id}")
    end
  end

  describe "Show" do
    setup [:create_conversation]

    test "displays conversation", %{conn: conn, conversation: conversation} do
      {:ok, _show_live, html} = live(conn, ~p"/conversations/#{conversation}")

      assert html =~ "Show Conversation"
      assert html =~ conversation.title
    end

    test "updates conversation and returns to show", %{conn: conn, conversation: conversation} do
      {:ok, show_live, _html} = live(conn, ~p"/conversations/#{conversation}")

      assert {:ok, form_live, _} =
               show_live
               |> element("a", "Edit")
               |> render_click()
               |> follow_redirect(conn, ~p"/conversations/#{conversation}/edit?return_to=show")

      assert render(form_live) =~ "Edit Conversation"

      assert form_live
             |> form("#conversation-form", conversation: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert {:ok, show_live, _html} =
               form_live
               |> form("#conversation-form", conversation: @update_attrs)
               |> render_submit()
               |> follow_redirect(conn, ~p"/conversations/#{conversation}")

      html = render(show_live)
      assert html =~ "Conversation updated successfully"
      assert html =~ "some updated title"
    end
  end
end
