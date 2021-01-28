defmodule EventsManager.Test.Consumer do
  use ExUnit.Case

  alias EventsManager.Consumer

  import ExUnit.CaptureLog

  test "init starts amqp channel and connection" do
    opts = [
      connection_uri: "amqp://test:test@127.0.0.1/vhost",
      exchange_topic: "test",
      consumer_module: EventsManager.Test.DummyConsumer
    ]

    {:ok, state} = EventsManager.Consumer.init(opts)

    assert state.channel == %AMQP.Channel{
             conn: %AMQP.Connection{pid: :conn_pid},
             pid: :channel_pid
           }

    assert state.consumer_module == EventsManager.Test.DummyConsumer
    assert state.queue == "nonode@nohost-test"
  end

  test "Consume returns ack" do
    payload = "my payload"
    delivery_tag = 1
    redelivered = false

    state = %Consumer.State{
      channel: %AMQP.Channel{
        conn: %AMQP.Connection{pid: :conn_pid},
        pid: :channel_pid
      },
      consumer_module: EventsManager.Test.DummyConsumer,
      queue: "test"
    }

    assert capture_log(fn ->
             assert Consumer.consume(state, delivery_tag, redelivered, payload) == {:ok, :ack}
           end) =~ "Sending ack for message"
  end

  test "Consume reject message due to error" do
    payload = "fail payload"
    delivery_tag = 1
    redelivered = false

    state = %Consumer.State{
      channel: %AMQP.Channel{
        conn: %AMQP.Connection{pid: :conn_pid},
        pid: :channel_pid
      },
      consumer_module: EventsManager.Test.DummyConsumer,
      queue: "test"
    }

    assert capture_log(fn ->
             assert Consumer.consume(state, delivery_tag, redelivered, payload) ==
                      {:rejected, :unexpected_error}
           end) =~ "Failed to process the message"
  end

  test "Consume reject message due to exception" do
    payload = "exception payload"
    delivery_tag = 1
    redelivered = false

    state = %Consumer.State{
      channel: %AMQP.Channel{
        conn: %AMQP.Connection{pid: :conn_pid},
        pid: :channel_pid
      },
      consumer_module: EventsManager.Test.DummyConsumer,
      queue: "test"
    }

    assert capture_log(fn ->
             assert Consumer.consume(state, delivery_tag, redelivered, payload) ==
                      {:error, %RuntimeError{message: "unexpected exception"}}
           end) =~ "An exception was thrown"
  end
end
