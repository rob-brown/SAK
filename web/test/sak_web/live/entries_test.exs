defmodule SakWeb.EntriesTest do
  use SakWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.PubSub
  alias Sak.Gateway

  @conversations [
    %{
      "id" => 1,
      "cwd" => "/work/alpha",
      "model" => "p/m",
      "name" => "Parent",
      "state" => "active"
    }
  ]

  setup do
    Application.put_env(:sak, :gateway_client, Sak.Test.FakeGatewayClient)
    Application.put_env(:sak, :fake_gateway_test_pid, self())

    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" => {:ok, %{"conversations" => @conversations}},
      "fork" => {:ok, %{"conversationId" => 7}}
    })

    on_exit(fn ->
      Application.delete_env(:sak, :gateway_client)
      Application.delete_env(:sak, :fake_gateway_test_pid)
      Application.delete_env(:sak, :fake_gateway_replies)
    end)

    :ok
  end

  defp press(view, key), do: render_hook(view, "key", %{"key" => key, "modifiers" => []})

  defp open_entries(conn) do
    {:ok, view, _html} = live(conn, ~p"/c/1")

    entries = [
      %{
        "id" => 8,
        "kind" => "pi.user",
        "model" => [%{"role" => "user", "content" => "Run echo please"}]
      },
      %{
        "id" => 11,
        "kind" => "pi.system",
        "model" => [%{"role" => "system", "content" => "", "toolsAdded" => [%{"name" => "bash"}]}]
      },
      %{
        "id" => 12,
        "kind" => "pi.assistant",
        "model" => [
          %{
            "role" => "assistant",
            "content" => [
              %{"type" => "toolCall", "name" => "bash", "arguments" => %{"command" => "echo hi"}}
            ]
          }
        ]
      },
      %{
        "id" => 14,
        "kind" => "pi.tool-result",
        "model" => [
          %{
            "role" => "toolResult",
            "toolName" => "bash",
            "isError" => false,
            "content" => [%{"type" => "text", "text" => "hi"}]
          }
        ]
      }
    ]

    PubSub.broadcast(
      Sak.PubSub,
      Gateway.conversation_topic(1),
      {:gateway_snapshot, 1, %{"entries" => entries}}
    )

    render(view)
    press(view, "]")
    view
  end

  test "] switches the chat pane to an Entries tab listing every entry including system and tool results",
       %{conn: conn} do
    # Arrange
    view = open_entries(conn)

    # Act
    rows = view |> element("#entries-pane") |> render()

    # Assert
    assert has_element?(view, "#entries-count", "4 entries")
    assert rows =~ "system"
    assert rows =~ "tools added: bash"
    assert rows =~ "→ bash echo hi"
    assert rows =~ "bash: hi"
    assert has_element?(view, "#history-row-14", "tool")
    assert has_element?(view, "#chat-history.hidden")
  end

  test "[ and ] switch back and forth", %{conn: conn} do
    # Arrange
    view = open_entries(conn)

    # Act
    press(view, "[")

    # Assert
    refute has_element?(view, "#entries-pane")
    refute has_element?(view, "#chat-history.hidden")
  end

  test "j, k and g move the selection, enter shows the full entry", %{conn: conn} do
    # Arrange
    view = open_entries(conn)

    # Act
    press(view, "g")
    press(view, "j")
    press(view, "enter")

    # Assert
    assert has_element?(view, "#history-row-11 pre", "toolsAdded")
    refute has_element?(view, "#history-row-8 pre")

    # Act
    press(view, "enter")

    # Assert
    refute has_element?(view, "#history-row-11 pre")
  end

  test "f forks from the selected entry and opens the new session", %{conn: conn} do
    # Arrange
    view = open_entries(conn)
    press(view, "g")
    press(view, "j")
    press(view, "j")

    # Act
    press(view, "f")

    # Assert
    assert_received {:gateway_request, "fork", %{"conversationId" => 1, "at" => 12}}
    assert_patch(view, ~p"/c/7")
    assert has_element?(view, "#status-line", "forked Parent at entry 3 (id 12)")
  end

  test "the entries tab is reset when another session is opened", %{conn: conn} do
    # Arrange
    view = open_entries(conn)

    # Act
    view |> element("#conversation-1") |> render_click()

    # Assert
    refute has_element?(view, "#entries-pane")
  end
end
