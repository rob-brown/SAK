defmodule Sak.GatewayIntegrationTest do
  use ExUnit.Case, async: true

  alias Sak.Gateway

  @moduletag :integration

  @gateway_dir Path.expand("../../../gateway", __DIR__)

  @tag :tmp_dir
  test "the real gateway creates, persists and lists a conversation", %{tmp_dir: tmp_dir} do
    # Arrange
    name = :"real_gateway_#{System.unique_integer([:positive])}"
    db = Path.join(tmp_dir, "sak.sqlite")

    start_supervised!(
      {Gateway,
       name: name,
       executable: System.find_executable("node"),
       args: ["src/main.ts"],
       cd: @gateway_dir,
       env: [{"SAK_DB", db}]}
    )

    # Act
    {:ok, %{"conversationId" => id}} =
      Gateway.request("create_conversation", %{"cwd" => tmp_dir}, server: name)

    {:ok, %{"conversations" => conversations}} =
      Gateway.request("list_conversations", %{}, server: name)

    # Assert
    assert [%{"id" => ^id, "cwd" => cwd}] = conversations
    assert cwd == tmp_dir
  end
end
