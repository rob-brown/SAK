defmodule Sak.NewSessionWizard do
  @moduledoc """
  The new-session wizard as a pure state machine: a directory, a model (when
  the endpoint offers a list) and an optional name, each with a default that
  `enter` accepts. The candidate list is computed on every state change and
  capped, so a large walked tree never reaches the browser; `hidden_count/1`
  says how many more matched.
  """

  alias Sak.FilePickerQuery
  alias Sak.FuzzyMatch

  @candidate_limit 50

  defstruct [
    :default_cwd,
    :cursor_cwd,
    :active_cwd,
    :default_model,
    :home,
    :index_root,
    step: :directory,
    steps: [:directory, :persona, :model, :name],
    personas: [],
    answers: %{},
    query: "",
    selected: 0,
    projects: [],
    models: [],
    directories: [],
    directories_loading?: false,
    candidates: [],
    hidden: 0
  ]

  @type step :: :directory | :persona | :model | :name
  @type candidate :: %{
          required(:value) => String.t(),
          required(:label) => String.t(),
          required(:kind) => :default | :project | :directory | :typed | :model | :persona,
          optional(:detail) => String.t()
        }
  @type answers :: %{
          cwd: String.t(),
          persona: String.t() | nil,
          model_id: String.t() | nil,
          name: String.t()
        }
  @type t :: %__MODULE__{}

  @spec new(String.t(), [String.t()], keyword()) :: t()
  def new(default_cwd, project_paths, hints \\ []) do
    models = Keyword.get(hints, :models, [])
    personas = Keyword.get(hints, :personas, [])

    refresh(%__MODULE__{
      default_cwd: default_cwd,
      cursor_cwd: hints[:cursor_cwd],
      active_cwd: hints[:active_cwd],
      default_model: hints[:default_model],
      home: Keyword.get_lazy(hints, :home, fn -> System.user_home() || default_cwd end),
      projects: project_paths,
      models: models,
      personas: personas,
      steps: steps(personas, models)
    })
  end

  @spec candidates(t()) :: [candidate()]
  def candidates(%__MODULE__{candidates: candidates}), do: candidates

  @spec hidden_count(t()) :: non_neg_integer()
  def hidden_count(%__MODULE__{hidden: hidden}), do: hidden

  @spec step_number(t()) :: pos_integer()
  def step_number(%__MODULE__{step: step, steps: steps}) do
    Enum.find_index(steps, &(&1 == step)) + 1
  end

  @spec step_count(t()) :: pos_integer()
  def step_count(%__MODULE__{steps: steps}) do
    length(steps)
  end

  @spec breadcrumb(t()) :: [String.t()]
  def breadcrumb(%__MODULE__{} = wizard) do
    for step <- Enum.take_while(wizard.steps, &(&1 != wizard.step)),
        Map.has_key?(wizard.answers, step) do
      answer_label(step, wizard.answers[step], wizard.home)
    end
  end

  @spec set_query(t(), String.t()) :: t()
  def set_query(%__MODULE__{} = wizard, query) do
    refresh(%{wizard | query: query, selected: 0})
  end

  @spec move(t(), integer()) :: t()
  def move(%__MODULE__{} = wizard, delta) do
    last = max(length(wizard.candidates) - 1, 0)
    %{wizard | selected: (wizard.selected + delta) |> max(0) |> min(last)}
  end

  @spec accept(t()) :: {:next, t()} | {:done, answers()} | :none
  def accept(%__MODULE__{step: :name} = wizard) do
    answers = wizard.answers

    {:done,
     %{
       cwd: answers.directory,
       model_id: Map.get(answers, :model),
       persona: Map.get(answers, :persona),
       name: String.trim(wizard.query)
     }}
  end

  def accept(%__MODULE__{} = wizard) do
    case Enum.at(wizard.candidates, wizard.selected) do
      nil -> :none
      %{value: value} -> {:next, advance(wizard, value)}
    end
  end

  @spec back(t()) :: {:ok, t()} | :cancel
  def back(%__MODULE__{step: step, steps: [step | _later]}), do: :cancel

  def back(%__MODULE__{} = wizard) do
    previous = Enum.at(wizard.steps, index_of(wizard) - 1)
    {:ok, refresh(%{wizard | step: previous, query: "", selected: 0})}
  end

  @spec request_index(t()) :: {t(), String.t() | nil}
  def request_index(%__MODULE__{step: :directory} = wizard) do
    {root, _remainder} = search_root(wizard)

    if root == wizard.index_root do
      {wizard, nil}
    else
      requested = %{wizard | index_root: root, directories: [], directories_loading?: true}
      {refresh(requested), root}
    end
  end

  def request_index(%__MODULE__{} = wizard) do
    {wizard, nil}
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

  defp steps(personas, models) do
    [:directory] ++ present(personas, :persona) ++ present(models, :model) ++ [:name]
  end

  defp present([], _step), do: []
  defp present(_items, step), do: [step]

  defp advance(wizard, value) do
    position = index_of(wizard) + 1
    answers = Map.put(wizard.answers, wizard.step, value)

    refresh(%{
      wizard
      | step: Enum.at(wizard.steps, position),
        answers: answers,
        query: "",
        selected: 0
    })
  end

  defp index_of(%__MODULE__{step: step, steps: steps}) do
    Enum.find_index(steps, &(&1 == step))
  end

  defp answer_label(:directory, path, home) do
    tilde(path, home)
  end

  defp answer_label(_step, value, _home), do: value

  defp refresh(wizard) do
    all = candidates_for(wizard)

    %{
      wizard
      | candidates: Enum.take(all, @candidate_limit),
        hidden: max(length(all) - @candidate_limit, 0)
    }
  end

  defp candidates_for(%{step: :directory} = wizard) do
    directory_candidates(wizard)
  end

  defp candidates_for(%{step: :persona} = wizard) do
    persona_candidates(wizard)
  end

  defp candidates_for(%{step: :model} = wizard) do
    model_candidates(wizard)
  end

  defp candidates_for(%{step: :name}), do: []

  defp persona_candidates(wizard) do
    by_name = Map.new(wizard.personas, &{&1["name"], &1})

    wizard.personas
    |> Enum.map(& &1["name"])
    |> FuzzyMatch.filter(wizard.query)
    |> Enum.map(fn name ->
      %{
        value: name,
        label: name,
        detail: by_name[name]["description"] || "",
        kind: if(name == "default", do: :default, else: :persona)
      }
    end)
  end

  defp model_candidates(wizard) do
    default = model_default(wizard)
    ordered = Enum.sort_by(wizard.models, &(&1 != default))

    ordered
    |> FuzzyMatch.filter(wizard.query)
    |> Enum.map(fn id ->
      %{value: id, label: id, kind: if(id == default, do: :default, else: :model)}
    end)
  end

  defp model_default(wizard) do
    persona = Enum.find(wizard.personas, &(&1["name"] == wizard.answers[:persona]))
    preferred = persona && persona["model"]

    if preferred in wizard.models do
      preferred
    else
      wizard.default_model
    end
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
      [
        wizard.answers[:directory],
        wizard.cursor_cwd,
        wizard.active_cwd,
        List.first(wizard.projects)
      ],
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

  defp typed_path("~", home) do
    {:ok, home}
  end

  defp typed_path("~/" <> rest, home) do
    {:ok, Path.join(home, rest)}
  end

  defp typed_path("/" <> _rest = path, _home) do
    {:ok, Path.expand(path)}
  end

  defp typed_path(_query, _home), do: :error

  defp candidate(path, kind, home) do
    %{value: path, label: tilde(path, home), kind: kind}
  end
end
