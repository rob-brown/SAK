defmodule SakWeb.PermissionModeTest do
  use SakWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @modes ["accept-edits", "ask", "auto"]

  setup do
    Application.put_env(:sak, :gateway_client, Sak.Test.FakeGatewayClient)
    Application.put_env(:sak, :fake_gateway_test_pid, self())

    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" =>
        {:ok, %{"conversations" => [%{"id" => 1, "cwd" => "/work/alpha", "model" => "m"}]}},
      "permission_mode" => {:ok, %{"mode" => "ask", "default" => "ask", "modes" => @modes}}
    })

    on_exit(fn ->
      Application.delete_env(:sak, :gateway_client)
      Application.delete_env(:sak, :fake_gateway_test_pid)
      Application.delete_env(:sak, :fake_gateway_replies)
    end)

    :ok
  end

  defp press(view, key), do: render_hook(view, "key", %{"key" => key, "modifiers" => []})

  defp open_picker(view) do
    press(view, ":")
    view |> form("#command-form", %{"query" => "permissions"}) |> render_change()
    view |> form("#command-form") |> render_submit()
  end

  test "the open session's mode is shown in the chat header" do
    # Arrange
    # Act
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")

    # Assert
    assert_received {:gateway_request, "permission_mode", %{"conversationId" => 1}}
    assert has_element?(view, "#permission-mode", "permissions: ask")
  end

  test "the permissions command opens a picker with the current mode selected" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")

    # Act
    open_picker(view)

    # Assert
    assert has_element?(view, "#mode-picker")
    assert has_element?(view, "#mode-ask", "in use")
    assert has_element?(view, "#mode-ask[data-selected=true]")
    assert has_element?(view, "#mode-auto", "Allow everything that no deny rule blocks")
  end

  test "j and enter apply the chosen mode to this session and update the header" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")
    open_picker(view)

    Application.put_env(:sak, :fake_gateway_replies, %{
      "permission_mode" => {:ok, %{"mode" => "auto", "default" => "ask", "modes" => @modes}}
    })

    # Act
    press(view, "j")
    press(view, "enter")

    # Assert
    assert_received {:gateway_request, "permission_mode",
                     %{"conversationId" => 1, "mode" => "auto"}}

    refute has_element?(view, "#mode-picker")
    assert has_element?(view, "#permission-mode", "permissions: auto")
  end

  test "escape closes the picker without changing anything, and clicking a row applies it" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")
    open_picker(view)

    # Act
    press(view, "escape")
    closed = not has_element?(view, "#mode-picker")
    open_picker(view)
    view |> element("#mode-accept-edits") |> render_click()

    # Assert
    assert closed
    refute_received {:gateway_request, "permission_mode", %{"mode" => "ask"}}
    assert_received {:gateway_request, "permission_mode", %{"mode" => "accept-edits"}}
  end

  test "without a session the command reports it instead of opening the picker" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/")

    # Act
    open_picker(view)

    # Assert
    refute has_element?(view, "#mode-picker")
  end
end
