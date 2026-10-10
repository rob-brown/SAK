defmodule Sak.Help do
  alias Sak.Keybindings

  @type row :: {:header, String.t()} | :blank | {:binding, Keybindings.entry()}
  @type search :: nil | {:term, String.t()} | {:binding, String.t()}

  @spec rows(atom(), atom() | nil, search()) :: [row()]
  def rows(focused_pane, sidebar_tab, search \\ nil) do
    local = focused_pane |> Keybindings.local(sidebar_tab) |> filter(search)
    global = (Keybindings.pane_focus_entries() ++ Keybindings.global()) |> filter(search)

    build_sections([{"Local", local}, {"Global", global}])
  end

  @spec parse_query(String.t()) :: search()
  def parse_query(""), do: nil

  def parse_query("@" <> key) do
    {:binding, key}
  end

  def parse_query(term) do
    {:term, term}
  end

  defp filter(entries, nil), do: entries

  defp filter(entries, {:term, term}) do
    Enum.filter(entries, fn {_key, description} ->
      String.contains?(String.downcase(description), String.downcase(term))
    end)
  end

  defp filter(entries, {:binding, key}) do
    Enum.filter(entries, fn {entry_key, _description} ->
      String.contains?(String.downcase(entry_key), String.downcase(key))
    end)
  end

  defp build_sections(sections) do
    sections
    |> Enum.reject(fn {_name, entries} -> entries == [] end)
    |> Enum.map(fn {name, entries} -> [{:header, name} | Enum.map(entries, &{:binding, &1})] end)
    |> Enum.intersperse([:blank])
    |> List.flatten()
  end
end
