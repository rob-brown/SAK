defmodule SakWeb.ChatLive.Models do
  @moduledoc false

  alias Phoenix.Component
  alias Sak.FuzzyMatch
  alias SakWeb.ChatLive.Sessions

  def open(socket) do
    case client().request("list_models", %{}) do
      {:ok, %{"current" => current, "models" => ids}} ->
        Component.assign(socket,
          last_notice: "",
          models: %{current: current_label(current), ids: ids, query: "", selected: 0},
          last_error: nil
        )

      {:ok, _unexpected} ->
        Component.assign(socket, last_error: "unexpected model list reply")

      {:error, reason} ->
        Component.assign(socket, last_error: reason)
    end
  end

  def search(%{assigns: %{models: models}} = socket, query) when is_map(models) do
    Component.assign(socket, models: %{models | query: query, selected: 0})
  end

  def search(socket, _query), do: socket

  def move(%{assigns: %{models: models}} = socket, delta) when is_map(models) do
    last = max(length(visible(models)) - 1, 0)
    selected = (models.selected + delta) |> max(0) |> min(last)
    Component.assign(socket, models: %{models | selected: selected})
  end

  def move(socket, _delta), do: socket

  def pick_index(%{assigns: %{models: models}} = socket, index) when is_map(models) do
    socket |> Component.assign(models: %{models | selected: index}) |> pick()
  end

  def pick_index(socket, _index), do: socket

  def pick(%{assigns: %{models: models}} = socket) when is_map(models) do
    case Enum.at(visible(models), models.selected) do
      nil -> socket
      model_id -> set(socket, model_id)
    end
  end

  def pick(socket), do: socket

  def close(socket) do
    Component.assign(socket, models: nil)
  end

  def visible(%{ids: ids, query: query}) do
    FuzzyMatch.filter(ids, query)
  end

  defp set(socket, model_id) do
    id = socket.assigns.current_id
    params = %{"modelId" => model_id} |> put_conversation(id)

    socket =
      case client().request("set_model", params) do
        {:ok, _result} ->
          socket
          |> close()
          |> Component.assign(last_error: nil, last_notice: notice(model_id, id))

        {:error, reason} ->
          Component.assign(socket, last_error: reason)
      end

    refresh_conversations(socket)
  end

  defp refresh_conversations(socket) do
    case client().request("list_conversations", %{}) do
      {:ok, %{"conversations" => conversations}} ->
        socket
        |> Component.assign(conversations: Enum.sort_by(conversations, & &1["id"], :desc))
        |> Sessions.rebuild()

      _other ->
        socket
    end
  end

  defp put_conversation(params, nil), do: params
  defp put_conversation(params, id), do: Map.put(params, "conversationId", id)

  defp notice(model_id, nil), do: "default model for new sessions: #{model_id}"
  defp notice(model_id, id), do: "session #{id} now uses #{model_id}"

  defp current_label(%{"provider" => provider, "modelId" => id}), do: "#{provider}/#{id}"
  defp current_label(_current), do: nil

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
