defmodule SakWeb.KeyboardTest do
  use SakWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.PubSub
  alias Sak.Gateway

  @conversations [
    %{"id" => 1, "cwd" => "/work/alpha", "model" => "m"},
    %{"id" => 2, "cwd" => "/work/beta", "model" => "m"}
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

  defp press(view, key), do: render_hook(view, "key", %{"key" => key, "modifiers" => []})

  defp snapshot(view, id, messages) do
    entries =
      messages
      |> Enum.with_index(1)
      |> Enum.map(fn {message, index} -> %{"id" => index, "model" => [message]} end)

    PubSub.broadcast(
      Sak.PubSub,
      Gateway.conversation_topic(id),
      {:gateway_snapshot, id, %{"entries" => entries}}
    )

    render(view)
  end

  defp assistant(blocks), do: %{"role" => "assistant", "content" => blocks}
  defp text(value), do: %{"type" => "text", "text" => value}

  test "question mark opens the keybinding help, which filters by description and by key", %{
    conn: conn
  } do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/")

    press(view, "0")

    # Act
    press(view, "?")
    opened = has_element?(view, "#help-overlay")
    view |> form("#help-search-form", %{"query" => "zoom"}) |> render_change()
    by_description = render(view |> element("#help-rows"))
    view |> form("#help-search-form", %{"query" => "@ctrl-d"}) |> render_change()
    by_key = render(view |> element("#help-rows"))
    press(view, "escape")

    # Assert
    assert opened
    assert by_description =~ "Zoom the focused pane"
    refute by_description =~ "Scroll one line down"
    assert by_key =~ "Scroll half a page down"
    refute by_key =~ "Zoom the focused pane"
    refute has_element?(view, "#help-overlay")
  end

  test "j, k and enter move through the sessions pane and open a conversation", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/")

    # Act
    press(view, "j")
    press(view, "enter")

    # Assert
    assert_patch(view, ~p"/c/2")
  end

  test "n in the sessions pane opens the wizard and enter creates the session", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/")

    # Act
    press(view, "n")
    opened = has_element?(view, "#wizard-overlay")
    view |> form("#wizard-form") |> render_submit()
    view |> form("#wizard-form") |> render_submit()

    # Assert
    assert opened
    assert_received {:gateway_request, "create_conversation", %{"cwd" => "/work/beta"}}
    assert_patch(view, ~p"/c/3")
    refute has_element?(view, "#wizard-overlay")
  end

  test "the wizard offers the personas and creates the session with the chosen one", %{conn: conn} do
    # Arrange
    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" => {:ok, %{"conversations" => @conversations}},
      "create_conversation" => {:ok, %{"conversationId" => 3}},
      "list_personas" =>
        {:ok,
         %{
           "personas" => [
             %{"name" => "default", "description" => "General", "model" => nil},
             %{"name" => "builder", "description" => "Implements a plan", "model" => nil}
           ]
         }}
    })

    {:ok, view, _html} = live(conn, ~p"/")
    press(view, "n")
    view |> form("#wizard-form") |> render_submit()

    # Act
    listed = has_element?(view, "#wizard-candidates li", "Implements a plan")
    view |> element("#wizard-candidate-1") |> render_click()
    view |> form("#wizard-form") |> render_submit()

    # Assert
    assert listed
    assert_received {:gateway_request, "create_conversation", %{"persona" => "builder"}}
  end

  test "escape closes the wizard without creating anything", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/")
    press(view, "n")

    # Act
    press(view, "escape")

    # Assert
    refute has_element?(view, "#wizard-overlay")
    refute_received {:gateway_request, "create_conversation", _}
  end

  test "slash searches the chat, highlights matches and n steps through them", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")
    snapshot(view, 1, [assistant([text("alpha beta")]), assistant([text("beta gamma")])])

    # Act
    press(view, "/")
    view |> form("#chat-search-form", %{"term" => "beta"}) |> render_change()
    view |> form("#chat-search-form") |> render_submit()
    press(view, "n")

    # Assert
    assert has_element?(view, "#entry-1-0 mark.chat-match", "beta")
    assert has_element?(view, "#entry-2-0 mark.chat-match", "beta")
    assert has_element?(view, "#chat-history-pane", "/beta (2 of 2)")
    assert has_element?(view, "#entry-1-0 mark.chat-match-current")
  end

  test "t hides thinking and the hidden thinking is not searchable", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")

    snapshot(view, 1, [
      assistant([%{"type" => "thinking", "thinking" => "secret plan"}, text("answer")])
    ])

    shown = render(view) =~ "secret plan"

    # Act
    press(view, "t")
    hidden = render(view) =~ "secret plan"

    # Assert
    assert shown
    refute hidden
    assert has_element?(view, "#chat-history-pane", "t off")
  end

  test "o toggles tool output while the tool call line stays visible", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")

    snapshot(view, 1, [
      assistant([%{"type" => "toolCall", "name" => "bash", "arguments" => %{"command" => "ls"}}]),
      %{
        "role" => "toolResult",
        "toolName" => "bash",
        "content" => [text("file-a file-b")],
        "isError" => false
      }
    ])

    before = render(view)

    # Act
    press(view, "o")
    after_toggle = render(view)

    # Assert
    assert before =~ "bash ls"
    refute before =~ "file-a"
    assert after_toggle =~ "file-a"
  end

  test "colon opens the command popup and clear starts a fresh session in the same directory",
       %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/c/1")

    # Act
    press(view, ":")
    opened = has_element?(view, "#command-overlay")
    view |> form("#command-form", %{"query" => "clear"}) |> render_change()
    view |> form("#command-form") |> render_submit()

    # Assert
    assert opened
    assert_received {:gateway_request, "create_conversation", %{"cwd" => "/work/alpha"}}
    assert_patch(view, ~p"/c/3")
  end

  test "the model command lists the endpoint's models and marks the one in use", %{conn: conn} do
    # Arrange
    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" => {:ok, %{"conversations" => @conversations}},
      "list_models" =>
        {:ok,
         %{
           "current" => %{"provider" => "openai-compatible", "modelId" => "ornith"},
           "models" => ["ornith", "qwen"]
         }}
    })

    {:ok, view, _html} = live(conn, ~p"/")

    # Act
    press(view, ":")
    view |> form("#command-form", %{"query" => "model"}) |> render_change()
    view |> form("#command-form") |> render_submit()
    listed = has_element?(view, "#models-list li", "qwen")
    view |> form("#models-search-form", %{"query" => "orn"}) |> render_change()

    # Assert
    assert listed
    assert has_element?(view, "#models-default", "openai-compatible/ornith")
    assert has_element?(view, "#models-list li", "in use")
    refute has_element?(view, "#models-list li", "qwen")
    press(view, "escape")
    refute has_element?(view, "#models-overlay")
  end

  test "picking a model sets it for the open conversation", %{conn: conn} do
    # Arrange
    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" => {:ok, %{"conversations" => @conversations}},
      "list_models" =>
        {:ok,
         %{
           "current" => %{"provider" => "openai-compatible", "modelId" => "ornith"},
           "models" => ["ornith", "qwen"]
         }}
    })

    {:ok, view, _html} = live(conn, ~p"/c/1")
    press(view, ":")
    view |> form("#command-form", %{"query" => "model"}) |> render_change()
    view |> form("#command-form") |> render_submit()

    # Act
    render_hook(view, "models_move", %{"delta" => 1})
    view |> form("#models-search-form") |> render_submit()

    # Assert
    assert_received {:gateway_request, "set_model", %{"modelId" => "qwen", "conversationId" => 1}}
    refute has_element?(view, "#models-overlay")
    assert has_element?(view, "#status-line", "session 1 now uses qwen")
  end

  test "picking a model with no conversation open sets the default for new ones", %{conn: conn} do
    # Arrange
    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" => {:ok, %{"conversations" => @conversations}},
      "list_models" =>
        {:ok, %{"current" => %{"provider" => "p", "modelId" => "a"}, "models" => ["a", "b"]}}
    })

    {:ok, view, _html} = live(conn, ~p"/")
    press(view, ":")
    view |> form("#command-form", %{"query" => "model"}) |> render_change()
    view |> form("#command-form") |> render_submit()

    # Act
    view |> element("#model-1") |> render_click()

    # Assert
    assert_received {:gateway_request, "set_model", params}
    assert params == %{"modelId" => "b"}
    assert has_element?(view, "#status-line", "default model for new sessions: b")
  end

  test "z zooms the focused pane and numbers focus panes", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/")

    # Act
    press(view, "0")
    press(view, "z")
    zoomed = render(view)
    press(view, "z")

    # Assert
    assert zoomed =~ "zoomed — z to restore"
    assert has_element?(view, "#sidebar.w-72")
  end
end
