defmodule Sak.TemplatePrompt do
  @moduledoc """
  The five questions behind the template form and the message they produce:
  each answer is wrapped in a tag named after its question, and unanswered
  questions are left out.
  """

  @questions [
    {"task", "Task", "What must be true when complete?"},
    {"context", "Context", "What does the agent need and what should it ignore?"},
    {"authority", "Authority", "What can the agent decide or change?"},
    {"evidence", "Evidence", "What proves the job is done?"},
    {"escalation", "Escalation", "When must the agent stop and ask?"}
  ]

  @spec fields() :: [
          %{name: String.t(), label: String.t(), question: String.t(), value: String.t()}
        ]
  def fields do
    Enum.map(@questions, fn {name, label, question} ->
      %{name: name, label: label, question: question, value: ""}
    end)
  end

  @spec build([%{name: String.t(), value: String.t()}]) :: String.t()
  def build(fields) do
    fields
    |> Enum.flat_map(fn field ->
      case String.trim(field.value) do
        "" -> []
        answer -> ["<#{field.name}>\n#{answer}\n</#{field.name}>"]
      end
    end)
    |> Enum.join("\n\n")
  end
end
