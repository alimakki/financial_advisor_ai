defmodule FinancialAdvisorAiWeb.PageController do
  use FinancialAdvisorAiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
