defmodule Sak.SessionRows do
  alias Sak.Project

  @type header :: %{
          label: String.t(),
          path: String.t(),
          count: non_neg_integer(),
          collapsed?: boolean()
        }
  @type row :: {:header, header()} | {:session, map()}
  @type key :: {:header, String.t()} | {:session, integer()}
  @type cache :: %{String.t() => String.t()}

  @spec build([map()], cache(), keyword()) :: {[row()], cache()}
  def build(sessions, cache, opts \\ []) do
    identify = Keyword.get(opts, :identify, &Project.identify/1)
    collapsed = Keyword.get(opts, :collapsed, MapSet.new())
    cache = Enum.reduce(sessions, cache, &remember(&2, cwd(&1), identify))
    labeled = Enum.map(sessions, &{Map.fetch!(cache, cwd(&1)), &1})

    rows =
      labeled
      |> Enum.uniq_by(fn {label, _session} -> label end)
      |> Enum.flat_map(fn {label, first} -> group(label, first, labeled, collapsed) end)

    {rows, cache}
  end

  @spec row_key(row() | nil) :: key() | nil
  def row_key({:header, %{label: label}}), do: {:header, label}
  def row_key({:session, session}), do: {:session, session["id"]}
  def row_key(nil), do: nil

  @spec index_of([row()], key() | nil) :: non_neg_integer() | nil
  def index_of(_rows, nil), do: nil

  def index_of(rows, key) do
    Enum.find_index(rows, &(row_key(&1) == key))
  end

  defp group(label, first, labeled, collapsed) do
    members = for {^label, session} <- labeled, do: {:session, session}
    collapsed? = MapSet.member?(collapsed, label)
    header = %{label: label, path: cwd(first), count: length(members), collapsed?: collapsed?}

    [{:header, header} | visible(members, collapsed?)]
  end

  defp remember(cache, path, identify) do
    Map.put_new_lazy(cache, path, fn -> identify.(path) end)
  end

  defp cwd(session), do: session["cwd"] || ""

  defp visible(_members, true), do: []
  defp visible(members, false), do: members
end
