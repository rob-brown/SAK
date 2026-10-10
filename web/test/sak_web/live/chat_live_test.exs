defmodule SakWeb.ChatLiveTest do
  use SakWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.PubSub
  alias Sak.Gateway

  @conversations [
    %{"id" => 1, "cwd" => "/work/alpha", "model" => "openai-compatible/m"},
    %{"id" => 2, "cwd" => "/work/beta", "model" => "openai-compatible/m"}
  ]

  setup do
    Application.put_env(:sak, :gateway_client, Sak.Test.FakeGatewayClient)
    Application.put_env(:sak, :fake_gateway_test_pid, self())

    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" => {:ok, %{"conversations" => @conversations}},
      "create_conversation" => {:ok, %{"conversationId" => 3}}
    })

    on_exit(fn ->
      Application.delete_env(:sak, :gateway_client)
      Application.delete_env(:sak, :fake_gateway_test_pid)
      Application.delete_env(:sak, :fake_gateway_replies)
    end)

    :ok
  end

  defp user_entry(id, text) do
    %{
      "kind" => "pi.user",
      "id" => id,
      "model" => [%{"role" => "user", "content" => text}]
    }
  end

  defp broadcast(id, message) do
    PubSub.broadcast(Sak.PubSub, Gateway.conversation_topic(id), message)
  end

  test "lists conversations and shows the empty state when none is selected", %{conn: conn} do
    # Arrange
    # Act
    {:ok, view, _html} = live(conn, ~p"/")

    # Assert
    assert has_element?(view, "#no-session")
    assert has_element?(view, "#conversation-1")
    assert has_element?(view, "#conversation-2")
    refute has_element?(view, "#prompt-form-0")
  end

  test "selecting a conversation attaches and renders the snapshot", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")
    assert_received {:gateway_request, "attach", %{"conversationId" => 1}}

    # Act
    broadcast(1, {:gateway_snapshot, 1, %{"entries" => [user_entry(7, "hello world")]}})
    _ = render(view)

    # Assert
    assert has_element?(view, "#entry-7-0", "hello world")
    refute has_element?(view, "#no-session")
    assert has_element?(view, "#prompt-form-0")
  end

  test "streamed events replace the live message with the final entry", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")
    broadcast(1, {:gateway_snapshot, 1, %{"entries" => []}})
    _ = render(view)

    start = %{"type" => "message_start", "message" => %{"role" => "assistant", "content" => []}}

    delta = %{
      "type" => "message_update",
      "changes" => [
        %{
          "type" => "text_start",
          "contentIndex" => 0,
          "block" => %{"type" => "text", "text" => "partial"}
        }
      ]
    }

    final = %{
      "type" => "message_end",
      "entry" => %{
        "id" => 11,
        "model" => [
          %{"role" => "assistant", "content" => [%{"type" => "text", "text" => "final answer"}]}
        ]
      }
    }

    # Act
    broadcast(1, {:gateway_events, 1, [start, delta]})
    live_rendered = render(view)
    broadcast(1, {:gateway_events, 1, [final]})
    settled = render(view)

    # Assert
    assert live_rendered =~ "partial"
    refute has_element?(view, "#live")
    assert settled =~ "final answer"
    refute settled =~ "partial"
  end

  test "markdown is rendered and raw html is dropped", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")

    snapshot = %{
      "entries" => [
        user_entry(7, "**not bold**"),
        %{
          "id" => 8,
          "model" => [
            %{
              "role" => "assistant",
              "content" => [%{"type" => "text", "text" => "**bold** <b>raw</b>"}]
            }
          ]
        }
      ]
    }

    # Act
    broadcast(1, {:gateway_snapshot, 1, snapshot})
    _ = render(view)

    # Assert
    assert has_element?(view, "#entry-8-0 strong", "bold")
    refute has_element?(view, "#entry-8-0 b")
    assert has_element?(view, "#entry-7-0 strong", "not bold")
  end

  test "usage shows in the status line", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")
    usage = %{"models" => %{"m" => %{"totalTokens" => 321}}}

    # Act
    broadcast(1, {:gateway_events, 1, [%{"type" => "usage_changed", "usage" => usage}]})
    _ = render(view)

    # Assert
    assert has_element?(view, "#status-line", "321 tokens")
  end

  test "events for another conversation are ignored", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")

    # Act
    send(view.pid, {:gateway_snapshot, 2, %{"entries" => [user_entry(9, "not mine")]}})
    html = render(view)

    # Assert
    refute html =~ "not mine"
  end

  test "sending a message submits it with steer and a request id", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")

    # Act
    view |> form("#prompt-form-0", %{"content" => "  do the thing  "}) |> render_submit()

    # Assert
    assert_received {:gateway_request, "submit",
                     %{
                       "conversationId" => 1,
                       "content" => "do the thing",
                       "whenBusy" => "steer",
                       "requestId" => request_id
                     }}

    assert is_binary(request_id)
  end

  test "a blank message is not submitted", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")

    # Act
    view |> form("#prompt-form-0", %{"content" => "   "}) |> render_submit()

    # Assert
    refute_received {:gateway_request, "submit", _}
  end

  test "the abort button appears while running and aborts the conversation", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")
    refute has_element?(view, "#abort-button")

    # Act
    broadcast(1, {:gateway_events, 1, [%{"type" => "run_start"}]})
    _ = render(view)
    shown = has_element?(view, "#abort-button")
    view |> element("#abort-button") |> render_click()

    # Assert
    assert shown
    assert_received {:gateway_request, "abort", %{"conversationId" => 1}}
  end

  test "a gateway restart re-attaches the current conversation", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")
    assert_received {:gateway_request, "attach", _}

    # Act
    PubSub.broadcast(Sak.PubSub, Gateway.started_topic(), :gateway_started)
    _ = render(view)

    # Assert
    assert_received {:gateway_request, "attach", %{"conversationId" => 1}}
  end

  test "a gateway error is shown in the status line", %{conn: conn} do
    # Arrange
    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" => {:ok, %{"conversations" => []}},
      "submit" => {:error, "unknown conversation 1"}
    })

    {:ok, view, _html} = live(conn, ~p"/c/1")

    # Act
    view |> form("#prompt-form-0", %{"content" => "hi"}) |> render_submit()

    # Assert
    assert has_element?(view, "#status-line", "unknown conversation 1")
  end
end
