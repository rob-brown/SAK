defmodule Sak.FileIndex do
  @skip_entries ~w(.git _build deps node_modules .elixir_ls cover)
  @protected_home_entries ~w(Desktop Documents Downloads Library Movies Music Pictures Public)
  @default_limit 20_000

  @type kind :: :files | :directories

  @spec list(String.t(), keyword()) :: [String.t()]
  def list(root, opts \\ []) do
    walk_opts = %{
      kind: Keyword.get(opts, :kind, :files),
      limit: Keyword.get(opts, :limit, @default_limit),
      home: Keyword.get_lazy(opts, :home, &System.user_home/0)
    }

    queue = :queue.in({"", root}, :queue.new())
    {entries, _count} = walk(queue, [], 0, walk_opts)
    Enum.reverse(entries)
  end

  defp walk(queue, entries, count, opts) do
    case :queue.out(queue) do
      {:empty, _queue} ->
        {entries, count}

      {{:value, {relative, absolute}}, rest} ->
        visit_directory(absolute, relative, rest, entries, count, opts)
    end
  end

  defp visit_directory(_absolute, _relative, queue, entries, count, opts)
       when count >= opts.limit do
    walk(queue, entries, count, opts)
  end

  defp visit_directory(absolute, relative, queue, entries, count, opts) do
    case File.ls(absolute) do
      {:ok, names} ->
        {queue, entries, count} =
          visit_entries(Enum.sort(names), absolute, relative, queue, entries, count, opts)

        walk(queue, entries, count, opts)

      {:error, _reason} ->
        walk(queue, entries, count, opts)
    end
  end

  defp visit_entries([], _absolute, _relative, queue, entries, count, _opts) do
    {queue, entries, count}
  end

  defp visit_entries(_names, _absolute, _relative, queue, entries, count, opts)
       when count >= opts.limit do
    {queue, entries, count}
  end

  defp visit_entries([name | rest], absolute, relative, queue, entries, count, opts) do
    {queue, entries, count} =
      if skip?(name, absolute, relative, opts) do
        {queue, entries, count}
      else
        visit_entry(name, absolute, relative, queue, entries, count, opts)
      end

    visit_entries(rest, absolute, relative, queue, entries, count, opts)
  end

  defp visit_entry(name, absolute, relative, queue, entries, count, opts) do
    entry_relative = join_relative(relative, name)
    entry_absolute = Path.join(absolute, name)

    case File.lstat(entry_absolute) do
      {:ok, %File.Stat{type: type}} ->
        record(type, opts.kind, entry_relative, entry_absolute, queue, entries, count)

      {:error, _reason} ->
        {queue, entries, count}
    end
  end

  defp record(:directory, :directories, relative, absolute, queue, entries, count) do
    {:queue.in({relative, absolute}, queue), [relative | entries], count + 1}
  end

  defp record(:directory, :files, relative, absolute, queue, entries, count) do
    {:queue.in({relative, absolute}, queue), entries, count}
  end

  defp record(:regular, :files, relative, _absolute, queue, entries, count) do
    {queue, [relative | entries], count + 1}
  end

  defp record(_type, _kind, _relative, _absolute, queue, entries, count) do
    {queue, entries, count}
  end

  defp skip?(name, absolute, relative, opts) do
    name in @skip_entries or
      hidden_directory?(name, opts.kind) or
      protected_home_entry?(name, absolute, relative, opts.home)
  end

  defp hidden_directory?(name, :directories) do
    String.starts_with?(name, ".")
  end

  defp hidden_directory?(_name, :files), do: false

  defp protected_home_entry?(name, absolute, "", home) when is_binary(home) do
    name in @protected_home_entries and Path.expand(absolute) == Path.expand(home)
  end

  defp protected_home_entry?(_name, _absolute, _relative, _home), do: false

  defp join_relative("", name), do: name

  defp join_relative(relative, name) do
    relative <> "/" <> name
  end
end
