defmodule SakWeb.ChatLive.TemplateForm do
  @moduledoc false

  alias Phoenix.Component
  alias Phoenix.LiveView
  alias Sak.TemplatePrompt

  def open(%{assigns: %{template_draft: draft}} = socket) when is_map(draft) do
    Component.assign(socket, template_form: draft)
  end

  def open(socket) do
    Component.assign(socket, template_form: %{fields: TemplatePrompt.fields(), index: 0})
  end

  def change(%{assigns: %{template_form: form}} = socket, values) when is_map(form) do
    fields = Enum.map(form.fields, &%{&1 | value: Map.get(values, &1.name, &1.value)})
    Component.assign(socket, template_form: %{form | fields: fields})
  end

  def change(socket, _values), do: socket

  def move(%{assigns: %{template_form: form}} = socket, delta) when is_map(form) do
    count = length(form.fields)

    Component.assign(socket,
      template_form: %{form | index: Integer.mod(form.index + delta, count)}
    )
  end

  def move(socket, _delta), do: socket

  def select(%{assigns: %{template_form: form}} = socket, index) when is_map(form) do
    index = min(max(index, 0), length(form.fields) - 1)
    Component.assign(socket, template_form: %{form | index: index})
  end

  def select(socket, _index), do: socket

  def submit(%{assigns: %{template_form: form}} = socket, values) when is_map(form) do
    form = socket |> change(values) |> Map.fetch!(:assigns) |> Map.fetch!(:template_form)

    socket
    |> Component.assign(template_form: nil, template_draft: nil)
    |> LiveView.push_event("prompt_fill", %{text: TemplatePrompt.build(form.fields)})
  end

  def submit(socket, _values), do: socket

  def cancel(%{assigns: %{template_form: form}} = socket) when is_map(form) do
    Component.assign(socket, template_form: nil, template_draft: form)
  end

  def cancel(socket), do: socket
end
