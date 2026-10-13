defmodule SakWeb.TemplateFormTest do
  use SakWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

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

  defp open_template do
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")
    press(view, "T")
    view
  end

  test "capital T opens the template form and lower-case t does not" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")

    # Act
    press(view, "t")
    closed = has_element?(view, "#template-form")
    press(view, "T")

    # Assert
    refute closed
    assert has_element?(view, "#template-form")
  end

  test "field events switch between the questions in a loop" do
    # Arrange
    view = open_template()

    # Act
    render_hook(view, "template_field", %{"delta" => -1})

    # Assert
    refute has_element?(view, "#template-field-task:not(.hidden)")
    assert has_element?(view, "#template-field-escalation:not(.hidden)")
  end

  test "submitting pushes the tagged answers to the message box and closes the form" do
    # Arrange
    view = open_template()

    values = %{
      "task" => "Build feature X.",
      "context" => "",
      "authority" => "",
      "evidence" => "",
      "escalation" => "Ask before deleting."
    }

    # Act
    view |> form("#template-form", %{"values" => values}) |> render_submit()

    # Assert
    refute has_element?(view, "#template-form")

    assert_push_event(view, "prompt_fill", %{
      text:
        "<task>\nBuild feature X.\n</task>\n\n<escalation>\nAsk before deleting.\n</escalation>"
    })
  end

  test "closing and reopening keeps the answers and the current question" do
    # Arrange
    view = open_template()

    view
    |> form("#template-form", %{"values" => %{"task" => "Build feature X."}})
    |> render_change()

    render_hook(view, "template_field", %{"delta" => 1})

    # Act
    press(view, "escape")
    press(view, "T")

    # Assert
    assert has_element?(view, "#template-answer-task", "Build feature X.")
    assert has_element?(view, "#template-field-context:not(.hidden)")
  end

  test "inserting clears the draft so the next template starts empty" do
    # Arrange
    view = open_template()

    view
    |> form("#template-form", %{"values" => %{"task" => "Build feature X."}})
    |> render_change()

    view |> form("#template-form") |> render_submit()

    # Act
    press(view, "T")

    # Assert
    refute has_element?(view, "#template-answer-task", "Build feature X.")
  end

  test "escape closes the form without filling the message box" do
    # Arrange
    view = open_template()

    # Act
    press(view, "escape")

    # Assert
    refute has_element?(view, "#template-form")
    refute_push_event(view, "prompt_fill", _payload)
  end
end
