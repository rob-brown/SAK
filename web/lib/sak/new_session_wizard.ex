defmodule Sak.NewSessionWizard do
  @moduledoc """
  The new-session wizard as a pure state machine. It asks for a directory,
  with a default that `enter` accepts. The directory list is computed on
  every state change and capped, so a large walked tree never reaches the
  browser; `hidden_count/1` says how many more matched.
  """

  alias Sak.FilePickerQuery
  alias Sak.FuzzyMatch

  @candidate_limit 50

  defstruct [
    :default_cwd,
    :cursor_cwd,
    :active_cwd,
    :home,
    :index_root,
    query: "",
    selected: 0,
    projects: [],
    directories: [],
    directories_loading?: false,
    candidates: [],
    hidden: 0
  ]

  @type candidate :: %{
          value: String.t(),
          label: String.t(),
          kind: :default | :project | :directory | :typed
        }
  @type t :: %__MODULE__{}

  @spec new(String.t(), [String.t()], keyword()) :: t()
  def new(default_cwd, project_paths, hints \\ []) do
    refresh(%__MODULE__{
      default_cwd: default_cwd,
      cursor_cwd: hints[:cursor_cwd],
      active_cwd: hints[:active_cwd],
      home: Keyword.get_lazy(hints, :home, fn -> System.user_home() || default_cwd end),
      projects: project_paths
    })
  end

  @spec candidates(t()) :: [candidate()]
  def candidates(%__MODULE__{candidates: candidates}), do: candidates

  @spec hidden_count(t()) :: non_neg_integer()
  def hidden_count(%__MODULE__{hidden: hidden}), do: hidden

  @spec set_query(t(), String.t()) :: t()
  def set_query(%__MODULE__{} = wizard, query) do
    refresh(%{wizard | query: query, selected: 0})
  end

  @spec move(t(), integer()) :: t()
  def move(%__MODULE__{} = wizard, delta) do
    last = max(length(wizard.candidates) - 1, 0)
    %{wizard | selected: (wizard.selected + delta) |> max(0) |> min(last)}
  end

  @spec accept(t()) :: {:done, String.t()} | :none
  def accept(%__MODULE__{} = wizard) do
    case Enum.at(wizard.candidates, wizard.selected) do
      nil -> :none
      %{value: value} -> {:done, value}
    end
  end

  @spec request_index(t()) :: {t(), String.t() | nil}
  def request_index(%__MODULE__{} = wizard) do
    {root, _remainder} = search_root(wizard)

    if root == wizard.index_root do
      {wizard, nil}
    else
      requested = %{wizard | index_root: root, directories: [], directories_loading?: true}
      {refresh(requested), root}
    end
  end

  @spec directories_loaded(t(), String.t(), [String.t()]) :: t()
  def directories_loaded(%__MODULE__{index_root: root} = wizard, root, directories) do
    refresh(%{wizard | directories: directories, directories_loading?: false})
  end

  def directories_loaded(%__MODULE__{} = wizard, _stale_root, _directories), do: wizard

  @spec tilde(String.t(), String.t()) :: String.t()
  def tilde(path, home) do
    cond do
      path == home -> "~"
      String.starts_with?(path, home <> "/") -> "~" <> String.replace_prefix(path, home, "")
      true -> path
    end
  end

  defp refresh(wizard) do
    all = directory_candidates(wizard)

    %{
      wizard
      | candidates: Enum.take(all, @candidate_limit),
        hidden: max(length(all) - @candidate_limit, 0)
    }
  end

  defp search_root(wizard) do
    base = default_directory(wizard)

    case FilePickerQuery.resolve(base, wizard.query, wizard.home) do
      {^base, remainder, ""} -> {wizard.home, remainder}
      {root, remainder, _label} -> {root, remainder}
    end
  end

  defp directory_candidates(wizard) do
    {_root, remainder} = search_root(wizard)

    known =
      [{default_directory(wizard), :default}] ++
        Enum.map(wizard.projects, &{&1, :project}) ++
        Enum.map(walked(wizard), &{&1, :directory})

    kind_by_path = known |> Enum.reverse() |> Map.new()
    paths = known |> Enum.map(fn {path, _kind} -> path end) |> Enum.uniq()
    path_by_label = Map.new(paths, &{tilde(&1, wizard.home), &1})

    matches =
      paths
      |> Enum.map(&tilde(&1, wizard.home))
      |> FuzzyMatch.filter(remainder)
      |> Enum.map(&Map.fetch!(path_by_label, &1))
      |> Enum.map(&candidate(&1, Map.fetch!(kind_by_path, &1), wizard.home))

    Enum.uniq_by(typed(wizard) ++ matches, & &1.value)
  end

  defp default_directory(wizard) do
    Enum.find(
      [wizard.cursor_cwd, wizard.active_cwd, List.first(wizard.projects)],
      wizard.default_cwd,
      &(&1 != nil)
    )
  end

  defp walked(%{index_root: nil}), do: []

  defp walked(%{index_root: root, directories: directories}) do
    Enum.map(directories, &Path.join(root, &1))
  end

  defp typed(%{query: query, home: home}) do
    with {:ok, path} <- typed_path(query, home),
         true <- File.dir?(path) do
      [candidate(path, :typed, home)]
    else
      _not_a_directory -> []
    end
  end

  defp typed_path("~", home), do: {:ok, home}
  defp typed_path("~/" <> rest, home), do: {:ok, Path.join(home, rest)}
  defp typed_path("/" <> _rest = path, _home), do: {:ok, Path.expand(path)}
  defp typed_path(_query, _home), do: :error

  defp candidate(path, kind, home) do
    %{value: path, label: tilde(path, home), kind: kind}
  end
end
