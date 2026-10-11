defmodule SakWeb.SubagentsTabTest do
  use SakWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @subagents [
    %{"id" => 7, "name" => "read the docs", "persona" => "reader", "live" => true},
    %{"id" => 6, "name" => "summarise", "persona" => "default", "live" => false}
  ]

  setup do
    Application.put_env(:sak, :gateway_client, Sak.Test.FakeGatewayClient)
    Application.put_env(:sak, :fake_gateway_test_pid, self())

    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" =>
        {:ok, %{"conversations" => [%{"id" => 1, "cwd" => "/work/alpha", "model" => "m"}]}},
      "list_subagents" => {:ok, %{"subagents" => @subagents}}
    })

    on_exit(fn ->
      Application.delete_env(:sak, :gateway_client)
      Application.delete_env(:sak, :fake_gateway_test_pid)
      Application.delete_env(:sak, :fake_gateway_replies)
    end)

    :ok
  end

  defp press(view, key), do: render_hook(view, "key", %{"key" => key, "modifiers" => []})

  defp open_tab do
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")
    view |> element("#tab-subagents") |> render_click()
    view
  end

  test "the tab lists running subagents by default and asks the gateway about the open session" do
    # Arrange
    # Act
    view = open_tab()

    # Assert
    assert_received {:gateway_request, "list_subagents", %{"conversationId" => 1}}
    assert has_element?(view, "#subagent-7", "read the docs")
    refute has_element?(view, "#subagent-6")
    assert has_element?(view, "#subagents-count", "1 running · 1 finished")
    assert has_element?(view, "#chat-history.hidden")
  end

  test "a toggles finished subagents and x stops only a running one" do
    # Arrange
    view = open_tab()

    # Act
    press(view, "a")
    shown = has_element?(view, "#subagent-6", "summarise")
    press(view, "x")
    press(view, "j")
    press(view, "x")

    # Assert
    assert shown
    assert_received {:gateway_request, "abort", %{"conversationId" => 7}}
    refute_received {:gateway_request, "abort", %{"conversationId" => 6}}
  end

  test "[ and ] cycle through the three tabs" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")
    press(view, "0")

    # Act
    press(view, "]")
    press(view, "]")
    third = has_element?(view, "#subagents-pane")
    press(view, "]")
    first = not has_element?(view, "#subagents-pane") and not has_element?(view, "#entries-pane")
    press(view, "[")

    # Assert
    assert third
    assert first
    assert has_element?(view, "#subagents-pane")
  end
end
