defmodule FinancialAdvisorAiWeb.UserLive.Login do
  use FinancialAdvisorAiWeb, :live_view

  alias FinancialAdvisorAi.Accounts

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="mx-auto max-w-sm space-y-4">
        <.header class="text-center">
          <p>Log in</p>
          <:subtitle>
            <%= if @current_scope do %>
              You need to reauthenticate to perform sensitive actions on your account.
            <% else %>
              Don't have an account? <.link
                navigate={~p"/users/register"}
                class="font-semibold text-brand hover:underline"
                phx-no-format
              >Sign up</.link> for an account now.
            <% end %>
          </:subtitle>
        </.header>

        <div :if={local_mail_adapter?()} class="alert alert-info">
          <.icon name="hero-information-circle" class="size-6 shrink-0" />
          <div>
            <p>You are running the local mail adapter.</p>
            <p>
              To see sent emails, visit <.link href="/dev/mailbox" class="underline">the mailbox page</.link>.
            </p>
          </div>
        </div>

        <div class="flex flex-col items-center space-y-4 mt-8">
          <a
            href="/auth/google"
            class="w-full flex items-center justify-center gap-2 px-4 py-2 rounded-lg border border-gray-300 bg-white text-gray-700 font-semibold shadow hover:bg-gray-50 transition-colors text-base"
          >
            <span class="inline-block align-middle">
              <!-- Google G SVG -->
              <svg
                width="20"
                height="20"
                viewBox="0 0 20 20"
                fill="none"
                Log
                in
                with
                Google
                xmlns="http://www.w3.org/2000/svg"
              >
                <g clip-path="url(#clip0_993_771)">
                  <path
                    d="M19.805 10.2305C19.805 9.55078 19.7484 8.86719 19.6266 8.19922H10.2V12.0492H15.6406C15.4156 13.2742 14.6844 14.3305 13.6469 15.0172V17.2672H16.805C18.505 15.6836 19.805 13.2305 19.805 10.2305Z"
                    fill="#4285F4"
                  />
                  <path
                    d="M10.2 20C12.7 20 14.7844 19.1836 16.3094 17.6836L13.6469 15.0172C12.8156 15.5972 11.6844 15.9492 10.2 15.9492C7.78437 15.9492 5.74062 14.3305 5.01562 12.1836H1.75937V14.4992C3.33437 17.7305 6.51562 20 10.2 20Z"
                    fill="#34A853"
                  />
                  <path
                    d="M5.01562 12.1836C4.81562 11.6036 4.7 10.9836 4.7 10.3336C4.7 9.68359 4.81562 9.06359 5.01562 8.48359V6.16797H1.75937C1.13437 7.38359 0.8 8.81641 0.8 10.3336C0.8 11.8508 1.13437 13.2836 1.75937 14.4992L5.01562 12.1836Z"
                    fill="#FBBC05"
                  />
                  <path
                    d="M10.2 4.7168C11.5656 4.7168 12.7719 5.18359 13.7219 6.08359L16.3781 3.42734C14.7844 1.95078 12.7 1 10.2 1C6.51562 1 3.33437 3.26953 1.75937 6.16797L5.01562 8.48359C5.74062 6.33672 7.78437 4.7168 10.2 4.7168Z"
                    fill="#EA4335"
                  />
                </g>
                <defs>
                  <clipPath id="clip0_993_771">
                    <rect width="19" height="19" fill="white" transform="translate(0.8 1)" />
                  </clipPath>
                </defs>
              </svg>
            </span>
            <span>Log in with Google</span>
          </a>
        </div>
      </div>
    </Layouts.app>
    """
  end

  def mount(_params, _session, socket) do
    email =
      Phoenix.Flash.get(socket.assigns.flash, :email) ||
        get_in(socket.assigns, [:current_scope, Access.key(:user), Access.key(:email)])

    form = to_form(%{"email" => email}, as: "user")

    {:ok, assign(socket, form: form, trigger_submit: false)}
  end

  def handle_event("submit_password", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end

  def handle_event("submit_magic", %{"user" => %{"email" => email}}, socket) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_login_instructions(
        user,
        &url(~p"/users/log-in/#{&1}")
      )
    end

    info =
      "If your email is in our system, you will receive instructions for logging in shortly."

    {:noreply,
     socket
     |> put_flash(:info, info)
     |> push_navigate(to: ~p"/users/log-in")}
  end

  defp local_mail_adapter? do
    Application.get_env(:financial_advisor_ai, FinancialAdvisorAi.Mailer)[:adapter] ==
      Swoosh.Adapters.Local
  end
end
