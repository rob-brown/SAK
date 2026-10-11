defmodule SakWeb.UsageTest do
  use SakWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.PubSub
  alias Sak.Gateway

  setup do
    Application.put_env(:sak, :gateway_client, Sak.Test.FakeGatewayClient)
    Application.put_env(:sak, :fake_gateway_test_pid, self())

    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" =>
        {:ok, %{"conversations" => [%{"id" => 1, "cwd" => "/work/alpha", "model" => "m"}]}}
    })

    on_exit(fn ->
      Application.delete_env(:sak, :gateway_client)
      Application.delete_env(:sak, :fake_gateway_test_pid)
      Application.delete_env(:sak, :fake_gateway_replies)
    end)

    :ok
  end

  defp press(view, key), do: render_hook(view, "key", %{"key" => key, "modifiers" => []})

  defp entries do
    [
      %{
        "kind" => "pi.assistant",
        "id" => 11,
        "model" => [
          %{
            "role" => "assistant",
            "model" => "ornith",
            "content" => [%{"type" => "text", "text" => "working on it"}],
            "durationMs" => 2_400,
            "usage" => %{
              "input" => 1_200,
              "output" => 80,
              "cacheRead" => 0,
              "totalTokens" => 1_280
            }
          }
        ]
      },
      %{
        "kind" => "pi.tool-result",
        "id" => 12,
        "model" => [
          %{
            "role" => "toolResult",
            "toolName" => "bash",
            "isError" => false,
            "durationMs" => 310,
            "content" => [%{"type" => "text", "text" => "ok"}]
          }
        ]
      }
    ]
  end

  defp open_session do
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")

    PubSub.broadcast(
      Sak.PubSub,
      Gateway.conversation_topic(1),
      {:gateway_snapshot, 1, %{"entries" => entries()}}
    )

    render(view)
    view
  end

  test "each reply and tool result shows its time, and i hides and shows them" do
    # Arrange
    view = open_session()

    # Act
    shown = render(view)
    press(view, "i")
    hidden = render(view)
    press(view, "i")

    # Assert
    assert shown =~ "2.4 s · 1,200 in · 80 out"
    assert shown =~ "bash · 310 ms"
    refute hidden =~ "1,200 in"
    refute hidden =~ "bash · 310 ms"
    assert render(view) =~ "bash · 310 ms"
  end

  test "the usage command totals tokens and time per model and per tool" do
    # Arrange
    view = open_session()

    # Act
    press(view, ":")
    view |> form("#command-form", %{"query" => "usage"}) |> render_change()
    view |> form("#command-form") |> render_submit()

    # Assert
    assert has_element?(view, "#usage-overlay")
    assert has_element?(view, "#usage-totals", "1,280")
    assert has_element?(view, "#usage-totals", "2.4 s")
    assert has_element?(view, "#usage-model-ornith", "1 reply")
    assert has_element?(view, "#usage-tool-bash", "1 call")
    press(view, "escape")
    refute has_element?(view, "#usage-overlay")
  end

  test "the usage command without a session says so instead of opening" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/")

    # Act
    press(view, ":")
    view |> form("#command-form", %{"query" => "usage"}) |> render_change()
    view |> form("#command-form") |> render_submit()

    # Assert
    refute has_element?(view, "#usage-overlay")
  end
end
