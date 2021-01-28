defmodule AMQPMock.Basic do
  @moduledoc false
  def consume(_channel, _queue, _consumer_pid \\ nil, _opts \\ []) do
    {:ok, :rand.uniform(1000)}
  end

  def qos(_channel, _opts \\ []) do
    :ok
  end

  def ack(_channel, _tag, _opts \\ []) do
    :ok
  end

  def reject(_channel, _tag, _opts \\ []) do
    :ok
  end
end
