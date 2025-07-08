defmodule FinancialAdvisorAi.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      FinancialAdvisorAiWeb.Telemetry,
      FinancialAdvisorAi.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:financial_advisor_ai, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster,
       query: Application.get_env(:financial_advisor_ai, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: FinancialAdvisorAi.PubSub},
      # AI Agent Registry and Supervisor
      {Registry, keys: :unique, name: FinancialAdvisorAi.AI.AgentRegistry},
      FinancialAdvisorAi.AI.AgentSupervisor,
      # Start a worker by calling: FinancialAdvisorAi.Worker.start_link(arg)
      # {FinancialAdvisorAi.Worker, arg},
      # Start Oban before services that depend on it
      {Oban, oban_config()},
      # Start to serve requests, typically the last entry
      FinancialAdvisorAiWeb.Endpoint,
      FinancialAdvisorAi.AI.PollingWorker,
      FinancialAdvisorAi.AI.TokenRefreshScheduler
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: FinancialAdvisorAi.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    FinancialAdvisorAiWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end

  defp oban_config do
    Application.fetch_env!(:financial_advisor_ai, Oban)
  end
end
