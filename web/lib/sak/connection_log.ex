defmodule Sak.ConnectionLog do
  @max_entries 500

  @enforce_keys [:entries]
  defstruct [:entries]

  @type t :: %__MODULE__{entries: [String.t()]}

  @spec new() :: t()
  def new do
    %__MODULE__{entries: []}
  end

  @spec append(t(), String.t()) :: t()
  def append(%__MODULE__{entries: entries}, line) do
    %__MODULE__{entries: Enum.take(entries ++ [line], -@max_entries)}
  end

  @spec lines(t()) :: [String.t()]
  def lines(%__MODULE__{entries: entries}) do
    entries
  end
end
