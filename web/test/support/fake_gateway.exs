defmodule FakeGateway do
  def run do
    case IO.gets("") do
      :eof ->
        :ok

      line ->
        handle(JSON.decode!(line))
        run()
    end
  end

  defp handle(%{"type" => "boom"}) do
    System.halt(3)
  end

  defp handle(%{"type" => "attach", "id" => id, "conversationId" => conversation_id}) do
    reply(id, true, %{})

    push(%{
      "type" => "snapshot",
      "conversationId" => conversation_id,
      "snapshot" => %{"entries" => []}
    })

    push(%{
      "type" => "events",
      "conversationId" => conversation_id,
      "events" => [%{"type" => "run_start"}]
    })
  end

  defp handle(%{"type" => "fail", "id" => id}) do
    push(%{"type" => "reply", "id" => id, "ok" => false, "error" => "nope"})
  end

  defp handle(%{"type" => "ghost"}) do
    push(%{"type" => "reply", "id" => nil, "ok" => false, "error" => "invalid JSON"})
  end

  defp handle(%{"id" => id, "type" => type}) do
    reply(id, true, %{"echo" => type})
  end

  defp reply(id, ok, result) do
    push(%{"type" => "reply", "id" => id, "ok" => ok, "result" => result})
  end

  defp push(message) do
    IO.puts(JSON.encode!(message))
  end
end

FakeGateway.run()
