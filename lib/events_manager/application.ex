defmodule EventsManager.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children =
      Application.get_env(:events_manager, :consumers, [])
      |> Enum.map(& {EventsManager.Consumer, &1})

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: EventsManager.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
