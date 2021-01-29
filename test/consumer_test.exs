defmodule EventsManager.Test.Consumer do
  use ExUnit.Case

  alias EventsManager.Consumer
  alias EventsManager.Consumer.State

  import ExUnit.CaptureLog

  test "Connection setup" do
    connection_uri = "amqp://test:test@127.0.0.1/vhost"
    exchange_topic = "test"
    consumer_module = EventsManager.Test.DummyConsumer

    params = {:connect, connection_uri, exchange_topic, consumer_module}

    {:noreply, state} = EventsManager.Consumer.handle_info(params, %State{})

    assert state.channel == %AMQP.Channel{
             conn: %AMQP.Connection{pid: :conn_pid},
             pid: :channel_pid
           }

    assert state.consumer_module == EventsManager.Test.DummyConsumer
    assert state.queue == "nonode@nohost-test"
  end

  test "Connection error. Reconnecting" do
    connection_uri = "amqp://server_error"
    exchange_topic = "test"
    consumer_module = EventsManager.Test.DummyConsumer

    params = {:connect, connection_uri, exchange_topic, consumer_module}

    assert capture_log(fn ->
             {:noreply, state} = EventsManager.Consumer.handle_info(params, %State{})

             assert state == %State{}
           end) =~ "Failed to connect"
  end

  test "Consume returns ack" do
    payload = ~s/{"payload": "test"}/
    delivery_tag = 1
    redelivered = false

    state = %State{
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
    payload = ~s/{"payload": "fail"}/
    delivery_tag = 1
    redelivered = false

    state = %State{
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
    payload = ~s/{"payload": "exception"}/
    delivery_tag = 1
    redelivered = false

    state = %State{
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
