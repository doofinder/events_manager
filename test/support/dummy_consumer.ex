defmodule EventsManager.Test.DummyConsumer do
  @moduledoc false

  @spec consume_event(term) :: :ok | {:error, :unexpected_error}
  def consume_event(%{"payload" => "fail"}) do
    {:error, :unexpected_error}
  end

  def consume_event(%{"payload" => "exception"}) do
    raise "unexpected exception"
  end

  def consume_event(_event) do
    :ok
  end
end
