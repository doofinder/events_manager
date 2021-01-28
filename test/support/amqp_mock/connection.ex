defmodule AMQPMock.Connection do
  @moduledoc false
  def open("amqp://server_error") do
    {:error, :server_not_found}
  end

  def open(_uri) do
    {:ok, %AMQP.Connection{pid: :conn_pid}}
  end
end
