defmodule EventsManager.Consumer do
  @moduledoc """
  Events manager consumer Genserver.

  This Genserver do the connection to the RabbitMQ server,
  create a dedicated queue and bind it with the exchange.
  In the last step, EventsManager.Consumer register a callback
  function with the queue to start processing events.

  The messages are received one by one (prefetch_count) to guarantee
  that any message is not lost on a genserver failure.
  """
  use GenServer
  use AMQP

  require Logger

  # credo:disable-for-next-line
  @reconnect_interval Application.get_env(
                        :events_manager,
                        :reconnect_interval,
                        :timer.seconds(5)
                      )

  @env Mix.env()

  defmodule State do
    @moduledoc """
    Module to manage the State of the Consumer
    """
    defstruct [:channel, :queue, :consumer_functions]

    @typedoc """
    Type to manage `EventsManager.Consumer` state. Stores
    the Rabbit connection channel, the queue name and
    the consumer functions.
    """
    @type t :: %__MODULE__{
            channel: Channel.t() | nil,
            queue: Basic.queue() | nil,
            consumer_functions: [atom] | nil
          }
  end

  def child_spec(arg) do
    %{
      id: Keyword.get(arg, :exchange_topic),
      start: {__MODULE__, :start_link, [arg]}
    }
  end

  @doc """
  Starts the Consumer Server with the given `opts` keyword list

  - `connection_uri`: AMQP connection uri
  - `exchange_topic`: RabbitMQ exchange name
  - `consumer_functions`: Functions that will receive the events

  example
  ```
  options =
    [
      connection_uri: "amqp://user:pass@server:<port>/vhost",
      exchange_topic: "test_topic_1",
      consumer_functions: [&Test.MyConsumer.my_function/1]
    ]

  {:ok, pid} = EventsManager.Consumer.start_link(options)
  ```
  """
  @spec start_link(Keyword.t()) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  @spec init(Keyword.t()) :: {:ok, State.t()}
  def init(opts) do
    connection_uri = Keyword.get(opts, :connection_uri)
    exchange = Keyword.get(opts, :exchange_topic)
    consumer_functions = Keyword.get(opts, :consumer_functions)

    send(self(), {:connect, connection_uri, exchange, consumer_functions})

    {:ok, %State{}}
  end

  # Manage connection with RabbitMQ
  def handle_info({:connect, connection_uri, exchange, consumer_functions} = params, state) do
    case get_module("Connection").open(connection_uri) do
      {:ok, conn} ->
        {chan, queue} = setup_connection(conn, exchange)
        {:noreply, %State{channel: chan, queue: queue, consumer_functions: consumer_functions}}

      {:error, reason} ->
        message = """
        [EventsManager] Failed to connect #{connection_uri}.
        With reason: #{inspect(reason)}
        Reconnecting after #{@reconnect_interval} ms ...
        """

        Logger.error(message)
        # Retry later
        Process.send_after(self(), params, @reconnect_interval)
        {:noreply, state}
    end
  end

  # Confirmation sent by the broker after registering this process as a consumer
  def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, state) do
    Logger.info("[EventsManager] Successfully consumer registered as #{consumer_tag}")
    {:noreply, state}
  end

  # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
  def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, state) do
    Logger.warn("[EventsManager] Consumer #{consumer_tag} cancelled")
    {:stop, :normal, state}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, state) do
    Logger.info("[EventsManager] Consumer #{consumer_tag} has been unregistered")
    {:noreply, state}
  end

  # Payload received, process it.
  def handle_info(
        {:basic_deliver, payload, %{delivery_tag: tag, redelivered: redelivered}},
        state
      ) do
    Logger.debug("[EventsManager] Received message with payload #{inspect(payload)}")
    consume(state, tag, redelivered, payload)
    {:noreply, state}
  end

  # Channel or Connection down. Stop GenServer. Will be restarted by Supervisor.
  def handle_info({:DOWN, _, :process, _pid, reason}, _) do
    Logger.debug("[EventsManager] Connection with RabbitMQ lost. Reason: #{inspect(reason)}")
    {:stop, {:connection_lost, reason}, nil}
  end

  @doc false
  @spec consume(State.t(), Basic.delivery_tag(), boolean, term) ::
          {:ok, :ack} | {:rejected, any} | {:error, term}
  def consume(state, tag, redelivered, payload) do
    {:ok, payload} = Jason.decode(payload)

    errors =
      state.consumer_functions
      |> Enum.map(& &1.(payload))
      |> Enum.reject(&(&1 == :ok))

    if length(errors) == 0 do
      Logger.debug("[EventsManager] Sending ack for message #{tag}")
      :ok = get_module("Basic").ack(state.channel, tag)
      {:ok, :ack}
    else
      Enum.each(errors, fn {_k, reason} ->
        message = """
        [EventsManager] Failed to process the message #{inspect(payload)}.
        Reason: #{inspect(reason)}
        """

        Logger.warn(message)
      end)

      :ok = get_module("Basic").reject(state.channel, tag, requeue: false)
      {:rejected, errors}
    end
  rescue
    # Requeue unless it's a redelivered message.
    # This means we will retry consuming a message once in case of exception
    # before we give up and have it moved to the error queue
    #
    # You might also want to catch :exit signal in production code.
    # Make sure you call ack, nack or reject otherwise comsumer will stop
    # receiving messages.
    exception ->
      message = """
      [EventsManager] An exception was thrown when was processing the message #{inspect(payload)}.
      Exception: #{inspect(exception)}
      """

      Logger.error(message)
      :ok = get_module("Basic").reject(state.channel, tag, requeue: not redelivered)
      {:error, exception}
  end

  defp setup_connection(conn, exchange) do
    {:ok, chan} = get_module("Channel").open(conn)
    # Get notifications when the connection goes down
    Process.monitor(conn.pid)
    Process.monitor(chan.pid)
    # Setup queue and bind exchange with channel
    queue = setup_queue(chan, exchange)

    # Limit unacknowledged messages to 1
    :ok = get_module("Basic").qos(chan, prefetch_count: 1)
    # Register the GenServer process as a consumer
    {:ok, _consumer_tag} = get_module("Basic").consume(chan, queue)

    {chan, queue}
  end

  # Set the queue name and bind to the desired exchange.
  # Returns the queue name
  @spec setup_queue(Channel.t(), Basic.exchange()) :: binary
  defp setup_queue(chan, exchange) do
    queue = get_queue_name(exchange)
    {:ok, _} = get_module("Queue").declare(chan, queue, auto_delete: true, exclusive: true)

    :ok = get_module("Exchange").declare(chan, exchange, :fanout, durable: true)
    :ok = get_module("Queue").bind(chan, queue, exchange)
    queue
  end

  @spec get_queue_name(Basic.exchange()) :: Basic.queue()
  defp get_queue_name(exchange) do
    random = random_string(5)
    "#{Node.self()}-#{exchange}-#{random}"
  end

  # Set manually module to avoid library configs
  defp get_module(name) do
    case @env do
      :test -> Module.concat(AMQPMock, name)
      _ -> Module.concat(AMQP, name)
    end
  end

  @spec random_string(integer) :: binary
  defp random_string(length) do
    alphabet = Enum.concat([?0..?9, ?A..?Z, ?a..?z])

    1..length
    |> Enum.map(fn _ -> Enum.random(alphabet) end)
    |> String.Chars.to_string()
  end
end
