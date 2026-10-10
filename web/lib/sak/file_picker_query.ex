defmodule Sak.FilePickerQuery do
  alias Sak.FuzzyMatch

  @spec resolve(String.t(), String.t(), String.t()) ::
          {root :: String.t(), remainder :: String.t(), label :: String.t()}
  def resolve(base_root, query, home \\ home())

  def resolve(_base_root, "~", home) do
    {home, "", "~/"}
  end

  def resolve(_base_root, "~/" <> rest, home) do
    {home, rest, "~/"}
  end

  def resolve(base_root, query, _home) do
    segments = String.split(query, "/")
    up_count = segments |> Enum.take_while(&(&1 == "..")) |> length()

    case up_count do
      0 ->
        {base_root, query, ""}

      _levels ->
        remainder = segments |> Enum.drop(up_count) |> Enum.join("/")
        root = Path.expand(Path.join([base_root | List.duplicate("..", up_count)]))
        {root, remainder, String.duplicate("../", up_count)}
    end
  end

  @picker_limit 50

  @spec picker_limit() :: pos_integer()
  def picker_limit do
    @picker_limit
  end

  @spec results(String.t(), String.t(), [String.t()], pos_integer() | :infinity) ::
          {label :: String.t(), [String.t()]}
  def results(base_root, query, files, limit \\ :infinity) do
    {_root, remainder, label} = resolve(base_root, query)
    {label, files |> FuzzyMatch.filter(remainder) |> take(limit)}
  end

  defp take(matches, :infinity) do
    matches
  end

  defp take(matches, limit) do
    Enum.take(matches, limit)
  end

  defp home do
    System.user_home() || File.cwd!()
  end
end
