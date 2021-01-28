defmodule AMQPMock.Exchange do
  @moduledoc false
  def declare(_channel, _exchange, :fanout, _opts \\ []) do
    :ok
  end
end
