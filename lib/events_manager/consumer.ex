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

  @doc """
  Invoked when the Consumer receive an event from RabbitMQ

  `event` is the message payload and the only callback parameter.

  The `consume_event` function should return `:ok` if the process of the event
  has been done without errors or a tuple `{:error, reason}` if there are
  any error.

  Example
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
  """
  @callback consume_event(event :: term) :: :ok | {:error, term}

  @reconnect_interval :timer.seconds(10)

  defmodule State do
    defstruct [:channel, :queue, :consumer_module]

    @typedoc """
    Type to manage `EventsManager.Consumer` state. Store
    the Rabbit connection channel, the queue name and
    the consumer module with implemented `EventsManager.Consumer`
    callback.
    """
    @type t :: %__MODULE__{
      channel: Channel.t,
      queue: Basic.queue,
      consumer_module: atom
    }
  end

  @doc """
  Starts the Consumer Server with the given `opts` keyword list

  - `connection_uri`: AMQP connection uri
  - `exchange_topic`: RabbitMQ exchange name
  - `consumer_module`: Module with `EventsManager.Consumer` callback implemented

  example
  ```
  options = [
      connection_uri: "amqp://user:pass@server:<port>/vhost",
      exchange_topic: "test_topic_1",
      consumer_module: Test.MyConsumer
    ]

  {:ok, pid} = EventsManager.Consumer.start_link(options)
  ```
  """
  @spec start_link(Keyword.t) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  @spec init(Keyword.t()) ::
          {:ok, state}
          | {:ok, state, timeout | :hibernate | {:continue, term}}
          | :ignore
          | {:stop, reason :: any}
        when state: State.t
  def init(opts) do
    connection_uri = Keyword.get(opts, :connection_uri)
    exchange = Keyword.get(opts, :exchange_topic)
    consumer_module = Keyword.get(opts, :consumer_module)

    {:ok, conn} = Connection.open(connection_uri)
    {:ok, chan} = Channel.open(conn)
    queue = setup_queue(chan, exchange)

    # Limit unacknowledged messages to 1
    :ok = Basic.qos(chan, prefetch_count: 1)
    # Register the GenServer process as a consumer
    {:ok, _consumer_tag} = Basic.consume(chan, queue)

    {:ok, %State{channel: chan, queue: queue, consumer_module: consumer_module}}
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
  def handle_info({:basic_deliver, payload, %{delivery_tag: tag, redelivered: redelivered}}, state) do
    Logger.debug("[EventsManager] Received message with payload #{inspect(payload)}")
    consume(state, tag, redelivered, payload)
    {:noreply, state}
  end

  # Manage the shutdown of the connection
  def handle_info({:DOWN, _, :process, _pid, reason}, _) do
    message = """
    [EventsManager] Connection with RabbitMQ server exited with reason:
    #{inspect(reason)}
    Reconnecting . . .
    """
    Logger.error(message)
    # Stop GenServer. Will be restarted by Supervisor.
    {:stop, {:connection_lost, reason}, nil}
  end

  # Set the queue name and bind to the desired exchange.
  # Returns the queue name
  @spec setup_queue(Channel.t, Basic.exchange) :: binary
  defp setup_queue(chan, exchange) do
    queue = get_queue_name(exchange)
    {:ok, _} = Queue.declare(chan, queue, auto_delete: true, exclusive: true)

    :ok = Exchange.declare(chan, exchange, :fanout, durable: true)
    :ok = Queue.bind(chan, queue, exchange)
    queue
  end

  @spec consume(State.t, Basic.delivery_tag, boolean, term) :: :ok
  defp consume(state, tag, redelivered, payload) do
    case apply(state.consumer_module, :consume_event, [payload]) do
      :ok ->
        Logger.debug("[EventsManager] Sending ack for message #{tag}")
        :ok = Basic.ack(state.channel, tag)

      {:error, reason} ->
        message = """
        [EventsManager] Failed to process the message #{inspect(payload)}.
        Reason: #{inspect(reason)}
        """

        Logger.warn(message)
        :ok = Basic.reject(state.channel, tag, requeue: false)
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
      :ok = Basic.reject(state.channel, tag, requeue: not redelivered)
  end

  @spec get_queue_name(Basic.exchange) :: Basic.queue
  defp get_queue_name(exchange) do
    "#{Node.self()}-#{exchange}"
  end
end
