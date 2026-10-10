defmodule SakWeb.ChatLiveIntegrationTest do
  use SakWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Phoenix.PubSub
  alias Sak.Gateway

  @moduletag :integration
  @moduletag timeout: 180_000

  @gateway_dir Path.expand("../../../../gateway", __DIR__)

  defp await_run_end do
    receive do
      {:gateway_events, _id, events} ->
        if Enum.any?(events, &(&1["type"] == "run_end")), do: :ok, else: await_run_end()
    after
      150_000 -> flunk("run did not finish")
    end
  end

  @tag :tmp_dir
  test "a prompt runs a tool through the real gateway and renders the result", %{
    conn: conn,
    tmp_dir: tmp_dir
  } do
    # Arrange
    start_supervised!(
      {Gateway,
       executable: System.find_executable("node"),
       args: ["src/main.ts"],
       cd: @gateway_dir,
       env: [{"SAK_DB", Path.join(tmp_dir, "sak.sqlite")}]}
    )

    {:ok, %{"conversationId" => id}} =
      Gateway.request("create_conversation", %{"cwd" => tmp_dir})

    PubSub.subscribe(Sak.PubSub, Gateway.conversation_topic(id))
    {:ok, view, _html} = live(conn, ~p"/c/#{id}")

    # Act
    view
    |> form("#prompt-form", %{"content" => "Write the word ok into ok.txt, then reply done."})
    |> render_submit()

    await_run_end()
    html = render(view)

    # Assert
    assert File.read!(Path.join(tmp_dir, "ok.txt")) =~ "ok"
    assert html =~ "write"
    assert has_element?(view, "[id^='entry-']")
  end
end
