# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :financial_advisor_ai, :scopes,
  user: [
    default: true,
    module: FinancialAdvisorAi.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: FinancialAdvisorAi.AccountsFixtures,
    test_login_helper: :register_and_log_in_user
  ]

config :financial_advisor_ai,
  ecto_repos: [FinancialAdvisorAi.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: {Uniq.UUID, :uuid7, []}]

# Configures the endpoint
config :financial_advisor_ai, FinancialAdvisorAiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: FinancialAdvisorAiWeb.ErrorHTML, json: FinancialAdvisorAiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: FinancialAdvisorAi.PubSub,
  live_view: [signing_salt: "iBYj8fw/"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :financial_advisor_ai, FinancialAdvisorAi.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  financial_advisor_ai: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.0.9",
  financial_advisor_ai: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :default_formatter, format: "$time $metadata[$level] $message\n"

# Configure Ueberauth for OAuth
config :ueberauth, Ueberauth,
  providers: [
    google:
      {Ueberauth.Strategy.Google,
       [
         default_scope:
           "email profile https://www.googleapis.com/auth/gmail.modify https://www.googleapis.com/auth/calendar.events.owned"
       ]}
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

config :financial_advisor_ai, Oban,
  repo: FinancialAdvisorAi.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [default: 10]
