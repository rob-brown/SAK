defmodule Sak.GatewayTest do
  use ExUnit.Case, async: true

  alias Phoenix.PubSub
  alias Sak.Gateway

  @fake Path.expand("../support/fake_gateway.exs", __DIR__)

  defp start_gateway(name) do
    start_supervised!(
      {Gateway, name: name, executable: System.find_executable("elixir"), args: [@fake]}
    )
  end

  defp unique_name do
    :"gateway_#{System.unique_integer([:positive])}"
  end

  test "request matches the reply to the caller by id" do
    # Arrange
    name = unique_name()
    start_gateway(name)

    # Act
    result = Gateway.request("list_conversations", %{}, server: name)

    # Assert
    assert {:ok, %{"echo" => "list_conversations"}} = result
  end

  test "a failed reply becomes an error tuple" do
    # Arrange
    name = unique_name()
    start_gateway(name)

    # Act
    result = Gateway.request("fail", %{}, server: name)

    # Assert
    assert {:error, "nope"} = result
  end

  test "pushed snapshot and events are broadcast on the conversation topic" do
    # Arrange
    name = unique_name()
    start_gateway(name)
    PubSub.subscribe(Sak.PubSub, Gateway.conversation_topic(7))

    # Act
    {:ok, _} = Gateway.request("attach", %{"conversationId" => 7}, server: name)

    # Assert
    assert_receive {:gateway_snapshot, 7, %{"entries" => []}}, 5_000
    assert_receive {:gateway_events, 7, [%{"type" => "run_start"}]}, 5_000
  end

  test "an uncorrelated error reply does not crash the gateway" do
    # Arrange
    name = unique_name()
    start_gateway(name)

    # Act
    ghost = Gateway.request("ghost", %{}, server: name, timeout: 300)
    result = Gateway.request("list_conversations", %{}, server: name)

    # Assert
    assert {:error, "gateway timed out"} = ghost
    assert {:ok, %{"echo" => "list_conversations"}} = result
  end

  test "pending requests fail and the process stops when the gateway exits" do
    # Arrange
    name = unique_name()
    pid = start_gateway(name)
    ref = Process.monitor(pid)

    # Act
    result = Gateway.request("boom", %{}, server: name)

    # Assert
    assert {:error, "gateway down"} = result
    assert_receive {:DOWN, ^ref, :process, ^pid, {:gateway_exited, 3}}, 5_000
  end

  test "the started topic announces each start" do
    # Arrange
    PubSub.subscribe(Sak.PubSub, Gateway.started_topic())

    # Act
    start_gateway(unique_name())

    # Assert
    assert_receive :gateway_started, 5_000
  end
end
