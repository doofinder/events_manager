defmodule AMQPMock.Channel do
  @moduledoc false
  def open(connection, _custom_consumer \\ nil) do
    {:ok, %AMQP.Channel{conn: connection, pid: :channel_pid}}
  end
end
