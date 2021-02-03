# EventsManager

**This app connect with RabbitMQ to work as consumer**

Events manager is an application to manage events sent by RabbitMQ using
AMQP protocol. When an event is received Events manager route the event
payload to your function callback to execute something (act as consumer).

Events manager, manage RabbitMQ connection, exchange and queues configuration,
messaging acknowledge and you only need to provide the function callback to
do something with the event message. Events manager control RabbitMQ outages 
reconnecting with the server.

Take in mind that the payload received by ampq should be json string that is 
parsed to elixir native term before call your consumer function

## Installation

The package can be installed by adding `events_manager` repository
to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:events_manager, github: "doofinder/events_manager", tag: "1.2.0"}
  ]
end
```

## How to use

To use EventsManager you need two things:

### Implement the EventsManager.Consumer behaviour

```elixir
defmodule Test.MyConsumer do
  @behaviour EventsManager.Consumer

  @impl true
  @spec consume_event(event :: term) :: :ok | {:error, term}
  def consume_event(event) do
    IO.inspect(event)

    :ok
  end
end
```

The `consume_event` function should return `:ok` if the process of the event
has been done without errors or a tuple `{:error, reason}` if there are
any error on the process the message won't be re-enqueued and a log will
be produced.

If a exception is raised when consuming the event, the message will be
re-enqueued to process again later.

### Put in the configuration

You need to configure EventsManager through application configuration.

Example of `config.exs`

```elixir
import Config

config :events_manager,
  consumers: [
    [
      connection_uri: "amqp://user:pass@server:<port>/vhost",
      exchange_topic: "test_topic_1",
      consumer_module: Test.MyConsumer
    ],
    [
      connection_uri: "amqp://user:pass@server:<port>/vhost",
      exchange_topic: "test_topic_2",
      consumer_module: Test.MyAnotherConsumer
    ]
  ],
  reconnect_interval: :timer.seconds(5)

import_config "#{Mix.env()}.exs"
```

Where 
- `consumers` is a list of:
  - `connection_uri` is a connection uri defined by [RabbitMQ URI spec](https://www.rabbitmq.com/uri-spec.html)
  - `exchange_topic` is a binary string with the name of the topic (RabbitMQ exchange)
  - `consumer_module` is the Module that implements the `EventsManager.Consumer` behaviour
- `reconnect_interval` is the wait time before try to reconnect again with RabbitMQ server


## What is the magic?

EventsManager is an Elixir application with a supervision tree
observing a Consumer Genserver (one per consumer) to guarantee
the resilience of the service and manage all possible adversities
that will can happen.
