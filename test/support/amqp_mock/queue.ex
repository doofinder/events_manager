defmodule AMQPMock.Queue do
  @moduledoc false
  def bind(_channel, _queue, _exchange, _opts \\ []) do
    :ok
  end

  def declare(_channel, queue \\ "", _opts \\ []) do
    {:ok, %{queue: queue, message_count: 0, consumer_count: 0}}
  end
end
