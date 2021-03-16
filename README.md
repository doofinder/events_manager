# EventsManager

**This app connect with RabbitMQ to work as consumer**

Events manager is an application to manage events sent by RabbitMQ using
AMQP protocol. When an event is received Events manager route the event
payload to your function callback to execute something (act as consumer).

Events manager, manage RabbitMQ connection, exchange and queues configuration,
messaging acknowledge and you only need to provide the function callback to
do something with the event message. Events manager control RabbitMQ outages
reconnecting with the server.

Notice that the payload received by ampq should be json string that is
parsed to elixir native term before call your consumer function

## Installation

The package can be installed by adding `events_manager` repository
to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:events_manager, github: "doofinder/events_manager", tag: "2.0.0"}
  ]
end
```

## How to use

To use EventsManager you need two things:


### Setup the configuration

Example of `config.exs`

```elixir
import Config

config :events_manager,
  connection_uri: "amqp://user:pass@server:<port>/vhost",
  consumers: %{
    "test_topic_1" => [&Test.MyModule.my_function/1],
    "test_topic_2" => [&Test.MyModule.my_another_function/1, &Test.MyOtherModule.my_function/1],
  },
  reconnect_interval: :timer.seconds(5)

import_config "#{Mix.env()}.exs"
```

Where
- `connection_uri` is a connection uri defined by [RabbitMQ URI spec](https://www.rabbitmq.com/uri-spec.html)
- `consumers` is a map where the keys are the `exchange_topic` (RabbitMQ exchange) and the values are the functions that will receive the events.
- `reconnect_interval` is the wait time before try to reconnect again with RabbitMQ server


### Define a function to consume the events

```elixir
defmodule Test.MyModule do
  @spec my_function(event :: term) :: :ok | {:error, term}
  def my_function(event) do
    IO.inspect(event)

    :ok
  end
end
```

The function should return `:ok` if the process of the event
has been done without errors or a tuple `{:error, reason}` if there is
any error in any of the functions the message won't be re-enqueued and a log will
be produced.

If an exception is raised when consuming the event, the message will be
re-enqueued to process again later. But this will happen only once, so if it
fails twice it will be just rejected.


## What is the magic?

EventsManager is an Elixir application with a supervision tree
observing a Consumer Genserver (one per topic) to guarantee
the resilience of the service and manage all possible adversities
that can happen.
