defmodule Sak.Test.FakeGatewayClient do
  @moduledoc false

  def request(type, params) do
    send(Application.fetch_env!(:sak, :fake_gateway_test_pid), {:gateway_request, type, params})

    :sak
    |> Application.get_env(:fake_gateway_replies, %{})
    |> Map.get(type, {:ok, %{}})
  end
end
