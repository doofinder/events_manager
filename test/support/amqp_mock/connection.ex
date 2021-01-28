defmodule AMQPMock.Connection do
  @moduledoc false
  def open(_uri) do
    {:ok, %AMQP.Connection{pid: :conn_pid}}
  end
end
