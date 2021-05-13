defmodule EventsManager.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    connection_uri = Application.get_env(:events_manager, :connection_uri)
    consumers = Application.get_env(:events_manager, :consumers, [])

    children =
      Enum.map(consumers, fn {topic, functions} ->
        {EventsManager.Consumer,
         [
           connection_uri: connection_uri,
           exchange_topic: topic,
           consumer_functions: functions
         ]}
      end)

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options.
    # All consumers are under the same Supervisor. If RabbitMQ closes the
    # connection, all consumers are restarted in a brief period and can exceed
    # the maximum number of restarts. For that reason the max_restarts is
    # configured with the number of consumers, and max seconds has a smaller
    # window.
    opts = [strategy: :one_for_one, name: EventsManager.Supervisor,
            max_restarts: length(children) * 2,
            max_seconds: 1]

    Supervisor.start_link(children, opts)
  end
end
