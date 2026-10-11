defmodule SakWeb.ChatLive.SkillForm do
  @moduledoc false

  alias Phoenix.Component
  alias Sak.SkillPrompt

  def open(socket, skill) do
    fields =
      Enum.map(Map.get(skill, "arguments", []), fn argument ->
        %{
          name: argument["name"],
          description: argument["description"],
          required?: argument["required"] == true,
          value: argument["default"] || ""
        }
      end)

    socket =
      Component.assign(socket, skill_form: %{skill: skill, fields: fields, index: 0, error: nil})

    if fields == [], do: run(socket), else: socket
  end

  def change(%{assigns: %{skill_form: form}} = socket, values) when is_map(form) do
    fields = Enum.map(form.fields, &%{&1 | value: Map.get(values, &1.name, &1.value)})
    Component.assign(socket, skill_form: %{form | fields: fields, error: nil})
  end

  def change(socket, _values), do: socket

  def move(%{assigns: %{skill_form: form}} = socket, delta) when is_map(form) do
    index = (form.index + delta) |> max(0) |> min(length(form.fields) - 1)
    Component.assign(socket, skill_form: %{form | index: index})
  end

  def move(socket, _delta), do: socket

  def submit(%{assigns: %{skill_form: form}} = socket, values) when is_map(form) do
    socket = change(socket, values)
    form = socket.assigns.skill_form

    if form.index < length(form.fields) - 1, do: move(socket, 1), else: run(socket)
  end

  def submit(socket, _values), do: socket

  def run(%{assigns: %{skill_form: form}} = socket) when is_map(form) do
    case Enum.find_index(form.fields, &(&1.required? and String.trim(&1.value) == "")) do
      nil -> send_message(socket, form)
      missing -> require_field(socket, form, missing)
    end
  end

  def run(socket), do: socket

  def cancel(socket), do: Component.assign(socket, skill_form: nil)

  defp require_field(socket, form, index) do
    field = Enum.at(form.fields, index)
    error = "#{field.name} is required"
    Component.assign(socket, skill_form: %{form | index: index, error: error})
  end

  defp send_message(socket, form) do
    values = Map.new(form.fields, &{&1.name, &1.value})

    params = %{
      "conversationId" => socket.assigns.current_id,
      "content" => SkillPrompt.build(form.skill, values),
      "whenBusy" => "steer",
      "requestId" => request_id()
    }

    case client().request("submit", params) do
      {:ok, _result} ->
        Component.assign(socket,
          skill_form: nil,
          last_error: nil,
          last_notice: "ran skill #{form.skill["name"]}"
        )

      {:error, reason} ->
        Component.assign(socket, last_error: reason)
    end
  end

  defp request_id do
    16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  defp client do
    Application.get_env(:sak, :gateway_client, Sak.Gateway)
  end
end
