defmodule SakWeb.SessionsManagementTest do
  use SakWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @conversations [
    %{
      "id" => 1,
      "cwd" => "/work/alpha",
      "model" => "openai-compatible/qwen/qwen3.8",
      "name" => "Fix login",
      "state" => "active"
    },
    %{
      "id" => 2,
      "cwd" => "/work/alpha",
      "model" => "openai-compatible/ornith",
      "name" => nil,
      "state" => "active"
    },
    %{
      "id" => 3,
      "cwd" => "/work/beta",
      "model" => "openai-compatible/ornith",
      "name" => "Old idea",
      "state" => "archived"
    }
  ]

  setup do
    Application.put_env(:sak, :gateway_client, Sak.Test.FakeGatewayClient)
    Application.put_env(:sak, :fake_gateway_test_pid, self())

    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" => {:ok, %{"conversations" => @conversations}},
      "set_meta" => {:ok, %{}}
    })

    on_exit(fn ->
      Application.delete_env(:sak, :gateway_client)
      Application.delete_env(:sak, :fake_gateway_test_pid)
      Application.delete_env(:sak, :fake_gateway_replies)
    end)

    :ok
  end

  defp press(view, key), do: render_hook(view, "key", %{"key" => key, "modifiers" => []})

  defp cursor_to(view, index) do
    press(view, "1")
    for _ <- 1..10, do: press(view, "k")
    for _ <- 1..index//1, do: press(view, "j")
  end

  test "rows show the name, the model without its provider, and fall back to the id", %{
    conn: conn
  } do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/")

    # Act
    named = view |> element("#conversation-1") |> render()
    unnamed = view |> element("#conversation-2") |> render()

    # Assert
    assert named =~ "Fix login"
    assert named =~ "qwen/qwen3.8"
    refute named =~ "openai-compatible"
    assert unnamed =~ "#2"
  end

  test "archived sessions are hidden until A shows them", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/")
    hidden = has_element?(view, "#conversation-3")

    # Act
    press(view, "A")
    shown = has_element?(view, "#conversation-3", "archived")
    press(view, "A")

    # Assert
    refute hidden
    assert shown
    refute has_element?(view, "#conversation-3")
  end

  test "a archives the selected session and unarchives an archived one", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/")
    cursor_to(view, 2)

    # Act
    press(view, "a")

    # Assert
    assert_received {:gateway_request, "set_meta",
                     %{"conversationId" => 1, "state" => "archived"}}

    # Arrange
    press(view, "A")
    cursor_to(view, 1)

    # Act
    press(view, "a")

    # Assert
    assert_received {:gateway_request, "set_meta", %{"conversationId" => 3, "state" => "active"}}
  end

  test "d asks first and only deletes on enter", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/")
    cursor_to(view, 1)

    # Act
    press(view, "d")
    asked = has_element?(view, "#delete-confirm")
    press(view, "escape")
    cancelled = not has_element?(view, "#delete-confirm")
    press(view, "d")
    press(view, "enter")

    # Assert
    assert asked
    assert cancelled
    assert_received {:gateway_request, "set_meta", %{"conversationId" => 2, "state" => "deleted"}}
    refute has_element?(view, "#delete-confirm")
  end

  test "r renames the selected session and an empty name clears it", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/")
    cursor_to(view, 2)

    # Act
    press(view, "r")
    view |> form("#rename-form", %{"name" => "  Better name "}) |> render_submit()

    # Assert
    assert_received {:gateway_request, "set_meta",
                     %{"conversationId" => 1, "name" => "Better name"}}

    refute has_element?(view, "#rename-overlay")
  end

  test "slash filters sessions by name, directory or model and escape clears the filter", %{
    conn: conn
  } do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/")
    press(view, "1")

    # Act
    press(view, "/")
    view |> form("#sessions-filter-form", %{"term" => "login"}) |> render_change()
    by_name = {has_element?(view, "#conversation-1"), has_element?(view, "#conversation-2")}
    view |> form("#sessions-filter-form", %{"term" => "beta"}) |> render_change()
    by_directory = has_element?(view, "#sessions-pane", "no sessions yet")
    press(view, "escape")

    # Assert
    assert by_name == {true, false}
    assert by_directory
    assert has_element?(view, "#conversation-2")
    refute has_element?(view, "#sessions-filter-form")
  end

  test "sessions are grouped under their directory", %{conn: conn} do
    # Arrange
    {:ok, view, _html} = live(conn, ~p"/")

    # Act
    html = render(view)

    # Assert
    assert length(Regex.scan(~r/▾ \/work\/alpha/, html)) == 1
    assert has_element?(view, "#conversation-1")
    assert has_element?(view, "#conversation-2")
  end
end
