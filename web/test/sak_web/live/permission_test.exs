defmodule SakWeb.PermissionTest do
  use SakWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.PubSub
  alias Sak.Gateway

  @request %{
    "type" => "permission_request",
    "requestId" => "r1",
    "conversationId" => 1,
    "tool" => "bash",
    "arguments" => %{"command" => "make deploy"},
    "summary" => "make deploy"
  }

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

  defp send_request(view, request \\ @request) do
    PubSub.broadcast(
      Sak.PubSub,
      Gateway.conversation_topic(1),
      {:gateway_permission, 1, request}
    )

    render(view)
  end

  test "a request opens the dialog with what is about to run, and y allows it once" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")

    # Act
    send_request(view)
    shown = has_element?(view, "#permission-dialog", "Allow bash?")
    press(view, "y")

    # Assert
    assert shown
    assert has_element?(view, "#permission-summary", "make deploy") == false

    assert_received {:gateway_request, "permission_reply",
                     %{"requestId" => "r1", "approval" => "allow"}}
  end

  test "a request closes the command palette so the prompt is the only thing taking keys" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")
    press(view, ":")
    opened = has_element?(view, "#command-form")

    # Act
    send_request(view)

    # Assert
    assert opened
    refute has_element?(view, "#command-form")
    assert has_element?(view, "#permission-dialog", "Allow bash?")
    assert has_element?(view, "#sak[data-permission-open=true]")
    refute has_element?(view, "#sak[data-command-open=true]")
  end

  test "a request also closes the mode picker, the chat search and the sessions filter" do
    # Arrange
    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" =>
        {:ok, %{"conversations" => [%{"id" => 1, "cwd" => "/work/alpha", "model" => "m"}]}},
      "permission_mode" =>
        {:ok, %{"mode" => "ask", "default" => "ask", "modes" => ["accept-edits", "ask", "auto"]}}
    })

    {:ok, picker, _html} = live(build_conn(), ~p"/c/1")
    press(picker, ":")
    picker |> form("#command-form", %{"query" => "permissions"}) |> render_change()
    picker |> form("#command-form") |> render_submit()
    {:ok, search, _html} = live(build_conn(), ~p"/c/1")
    press(search, "/")
    {:ok, filter, _html} = live(build_conn(), ~p"/c/1")
    press(filter, "1")
    press(filter, "/")

    opened = [
      has_element?(picker, "#mode-picker"),
      has_element?(search, "#chat-search-form"),
      has_element?(filter, "#sessions-filter-form")
    ]

    # Act
    for view <- [picker, search, filter], do: send_request(view)

    # Assert
    assert opened == [true, true, true]
    refute has_element?(picker, "#mode-picker")
    refute has_element?(search, "#chat-search-form")
    refute has_element?(filter, "#sessions-filter-form")
    assert has_element?(filter, "#permission-dialog", "Allow bash?")
  end

  test "a request from a subagent says so" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")

    # Act
    send_request(view, Map.put(@request, "subagent", 12))

    # Assert
    assert has_element?(view, "#permission-subagent", "subagent #12")
  end

  test "a note from the judge is shown above the command" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")

    # Act
    send_request(
      view,
      Map.put(@request, "note", "Flagged by the judge as likely destructive (97%).")
    )

    # Assert
    assert has_element?(view, "#permission-note", "likely destructive (97%)")
    refute has_element?(view, "#permission-subagent")
  end

  test "a denies for the session grant, and n and escape deny" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")

    # Act
    send_request(view)
    press(view, "a")
    send_request(view, Map.put(@request, "requestId", "r2"))
    press(view, "n")
    send_request(view, Map.put(@request, "requestId", "r3"))
    press(view, "escape")

    # Assert
    assert_received {:gateway_request, "permission_reply",
                     %{"requestId" => "r1", "approval" => "allow_conversation"}}

    assert_received {:gateway_request, "permission_reply",
                     %{"requestId" => "r2", "approval" => "deny"}}

    assert_received {:gateway_request, "permission_reply",
                     %{"requestId" => "r3", "approval" => "deny"}}
  end

  test "requests are answered in order and the dialog says how many are waiting" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")
    send_request(view)

    # Act
    send_request(view, Map.merge(@request, %{"requestId" => "r2", "summary" => "ls"}))
    waiting = has_element?(view, "#permission-dialog", "1 more waiting")
    press(view, "y")

    # Assert
    assert waiting
    assert has_element?(view, "#permission-summary", "ls")
    assert has_element?(view, "#permission-dialog", "1 more waiting") == false
  end

  test "a resolved announcement closes the dialog without a reply, and clicking works too" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")
    send_request(view)

    # Act
    PubSub.broadcast(
      Sak.PubSub,
      Gateway.conversation_topic(1),
      {:gateway_permission_resolved, 1, "r1"}
    )

    closed = not (view |> render() |> String.contains?("permission-dialog"))
    send_request(view, Map.put(@request, "requestId", "r2"))
    view |> element("#permission-deny") |> render_click()

    # Assert
    assert closed
    refute_received {:gateway_request, "permission_reply", %{"requestId" => "r1"}}

    assert_received {:gateway_request, "permission_reply",
                     %{"requestId" => "r2", "approval" => "deny"}}
  end

  test "a request for another conversation is ignored" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")

    # Act
    send(view.pid, {:gateway_permission, 2, Map.put(@request, "conversationId", 2)})

    # Assert
    refute view |> render() |> String.contains?("permission-dialog")
  end
end
