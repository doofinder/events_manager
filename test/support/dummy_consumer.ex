defmodule EventsManager.Test.DummyConsumer do
  @moduledoc false
  @behaviour EventsManager.Consumer

  @spec consume_event(any) :: :ok | {:error, :unexpected_error}
  def consume_event("fail payload") do
    {:error, :unexpected_error}
  end

  def consume_event("exception payload") do
    raise "unexpected exception"
  end

  def consume_event(_event) do
    :ok
  end
end
