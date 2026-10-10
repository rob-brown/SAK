defmodule Sak.Project do
  @spec identify(String.t()) :: String.t()
  def identify(cwd) do
    case toplevel(cwd) do
      {:ok, toplevel} -> remote_or_basename(cwd, toplevel)
      :error -> cwd
    end
  end

  defp toplevel(cwd) do
    case git(cwd, ["rev-parse", "--show-toplevel"]) do
      {:ok, toplevel} -> {:ok, String.trim(toplevel)}
      :error -> :error
    end
  end

  defp remote_or_basename(cwd, toplevel) do
    case git(cwd, ["remote", "get-url", "origin"]) do
      {:ok, url} -> url |> String.trim() |> shorten_remote()
      :error -> Path.basename(toplevel)
    end
  end

  defp shorten_remote(url) do
    url
    |> String.replace(~r{^[a-zA-Z][a-zA-Z0-9+.-]*://}, "")
    |> String.replace(~r{^[^@/]+@}, "")
    |> String.replace(~r{^[^:/]+[:/]}, "")
    |> String.trim_trailing(".git")
  end

  defp git(cwd, args) do
    case System.cmd("git", ["-C", cwd | args], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {_output, _exit_code} -> :error
    end
  rescue
    ErlangError -> :error
  end
end
