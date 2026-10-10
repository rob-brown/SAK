defmodule SakWeb.ChatLive.Models do
  @moduledoc false

  alias Phoenix.Component
  alias Sak.FuzzyMatch

  def open(socket) do
    case client().request("list_models", %{}) do
      {:ok, %{"current" => current, "models" => ids}} ->
        Component.assign(socket,
          models: %{current: current_label(current), ids: ids, query: ""},
          last_error: nil
        )

      {:ok, _unexpected} ->
        Component.assign(socket, last_error: "unexpected model list reply")

      {:error, reason} ->
        Component.assign(socket, last_error: reason)
    end
  end

  def search(%{assigns: %{models: models}} = socket, query) when is_map(models) do
    Component.assign(socket, models: %{models | query: query})
  end

  def search(socket, _query), do: socket

  def close(socket) do
    Component.assign(socket, models: nil)
  end

  def visible(%{ids: ids, query: query}) do
    FuzzyMatch.filter(ids, query)
  end

  defp current_label(%{"provider" => provider, "modelId" => id}), do: "#{provider}/#{id}"
  defp current_label(_current), do: nil

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
