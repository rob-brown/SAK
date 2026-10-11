defmodule SakWeb.SkillCommandTest do
  use SakWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  @skills [
    %{
      "name" => "report",
      "description" => "Write a status report",
      "path" => "/work/alpha/.agents/skills/report/SKILL.md",
      "arguments" => [
        %{
          "name" => "topic",
          "description" => "What it is about",
          "default" => nil,
          "required" => true
        },
        %{"name" => "length", "description" => nil, "default" => "short", "required" => false}
      ]
    },
    %{
      "name" => "pdf",
      "description" => "Fill in PDF forms",
      "path" => "/work/alpha/.agents/skills/pdf/SKILL.md",
      "arguments" => []
    }
  ]

  setup do
    Application.put_env(:sak, :gateway_client, Sak.Test.FakeGatewayClient)
    Application.put_env(:sak, :fake_gateway_test_pid, self())

    Application.put_env(:sak, :fake_gateway_replies, %{
      "list_conversations" =>
        {:ok, %{"conversations" => [%{"id" => 1, "cwd" => "/work/alpha", "model" => "m"}]}},
      "list_skills" => {:ok, %{"skills" => @skills}}
    })

    on_exit(fn ->
      Application.delete_env(:sak, :gateway_client)
      Application.delete_env(:sak, :fake_gateway_test_pid)
      Application.delete_env(:sak, :fake_gateway_replies)
    end)

    :ok
  end

  defp press(view, key), do: render_hook(view, "key", %{"key" => key, "modifiers" => []})

  defp pick(view, query) do
    press(view, ":")
    view |> form("#command-form", %{"query" => query}) |> render_change()
    view |> form("#command-form") |> render_submit()
  end

  defp open_report do
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")
    pick(view, "report")
    view
  end

  test "skills appear in the command palette next to the built-in commands" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/c/1")

    # Act
    press(view, ":")
    view |> form("#command-form", %{"query" => "skill"}) |> render_change()
    html = render(view)

    # Assert
    assert_received {:gateway_request, "list_skills", %{"conversationId" => 1}}
    assert html =~ "skill:report"
    assert html =~ "Skill: Write a status report"
    assert html =~ "skill:pdf"
  end

  test "without an open session there are no skill commands and no request for them" do
    # Arrange
    {:ok, view, _html} = live(build_conn(), ~p"/")

    # Act
    press(view, ":")
    view |> form("#command-form", %{"query" => "skill"}) |> render_change()

    # Assert
    refute_received {:gateway_request, "list_skills", _}
    refute render(view) =~ "skill:report"
  end

  test "choosing a skill with arguments opens a form with its defaults and the first field current" do
    # Arrange
    # Act
    view = open_report()

    # Assert
    assert has_element?(view, "#skill-form", "Skill: report")
    assert has_element?(view, "#skill-field-topic", "What it is about")
    assert has_element?(view, "#skill-arg-topic[data-current=true]")
    assert has_element?(view, "#skill-arg-length[data-current=false][value=short]")
    refute_received {:gateway_request, "submit", _}
  end

  test "[ and ] move between the fields" do
    # Arrange
    view = open_report()

    # Act
    press(view, "]")
    second = has_element?(view, "#skill-arg-length[data-current=true]")
    press(view, "]")
    stays = has_element?(view, "#skill-arg-length[data-current=true]")
    press(view, "[")

    # Assert
    assert second
    assert stays
    assert has_element?(view, "#skill-arg-topic[data-current=true]")
  end

  test "enter moves to the next field, and on the last one runs the skill with the filled values" do
    # Arrange
    view = open_report()

    view
    |> form("#skill-form", %{"values" => %{"topic" => "Q3 results", "length" => "long"}})
    |> render_change()

    # Act
    view |> form("#skill-form") |> render_submit()
    moved = has_element?(view, "#skill-arg-length[data-current=true]")

    sent_early =
      Process.info(self(), :messages)
      |> elem(1)
      |> Enum.any?(&match?({:gateway_request, "submit", _}, &1))

    view |> form("#skill-form") |> render_submit()

    # Assert
    assert moved
    refute sent_early
    assert_received {:gateway_request, "submit", params}
    assert params["conversationId"] == 1
    assert params["content"] =~ ~s(Use the "report" skill)
    assert params["content"] =~ "/work/alpha/.agents/skills/report/SKILL.md"
    assert params["content"] =~ "- topic: Q3 results\n- length: long"
    refute has_element?(view, "#skill-form")
  end

  test "a missing required value keeps the form open on that field and sends nothing" do
    # Arrange
    view = open_report()
    press(view, "]")

    # Act
    view |> element("#skill-run") |> render_click()

    # Assert
    assert has_element?(view, "#skill-form-error", "topic is required")
    assert has_element?(view, "#skill-arg-topic[data-current=true]")
    refute_received {:gateway_request, "submit", _}
  end

  test "escape cancels without sending, and a skill without arguments runs straight away" do
    # Arrange
    view = open_report()

    # Act
    press(view, "escape")
    closed = not has_element?(view, "#skill-form")
    pick(view, "pdf")

    # Assert
    assert closed
    assert_received {:gateway_request, "submit", params}
    assert params["content"] =~ ~s(Use the "pdf" skill)
    refute params["content"] =~ "Arguments"
    refute has_element?(view, "#skill-form")
  end
end
