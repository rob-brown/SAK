defmodule Sak.NewSessionWizardTest do
  use ExUnit.Case, async: true

  alias Sak.NewSessionWizard

  @home "/home/me"

  defp wizard(projects \\ [], hints \\ []) do
    NewSessionWizard.new("/home/me/default", projects, [home: @home] ++ hints)
  end

  @models ["alpha-model", "beta-model"]

  defp walk(wizard) do
    {:next, wizard} = NewSessionWizard.accept(wizard)
    wizard
  end

  test "enter on every step accepts the defaults and finishes with the chosen directory and model" do
    # Arrange
    wizard = wizard([], models: @models, default_model: "beta-model")

    # Act
    on_model = walk(wizard)
    on_name = walk(on_model)
    result = NewSessionWizard.accept(on_name)

    # Assert
    assert on_model.step == :model
    assert [%{value: "beta-model", kind: :default} | _] = NewSessionWizard.candidates(on_model)
    assert on_name.step == :name
    assert result == {:done, %{cwd: "/home/me/default", model_id: "beta-model", name: ""}}
  end

  test "the name typed on the last step is trimmed and returned" do
    # Arrange
    on_name = [] |> wizard(models: @models) |> walk() |> walk()

    # Act
    result = on_name |> NewSessionWizard.set_query("  Refactor  ") |> NewSessionWizard.accept()

    # Assert
    assert {:done, %{name: "Refactor"}} = result
  end

  test "without models the model step is skipped" do
    # Arrange
    wizard = wizard()

    # Act
    on_name = walk(wizard)

    # Assert
    assert NewSessionWizard.step_count(wizard) == 2
    assert on_name.step == :name
    assert {:done, %{model_id: nil}} = NewSessionWizard.accept(on_name)
  end

  test "escape steps back and cancels from the first step" do
    # Arrange
    on_model = [] |> wizard(models: @models) |> walk()

    # Act
    back = NewSessionWizard.back(on_model)
    cancelled = NewSessionWizard.back(wizard())

    # Assert
    assert {:ok, %{step: :directory}} = back
    assert cancelled == :cancel
  end

  test "the directory under the sessions cursor becomes the default" do
    # Arrange
    wizard = wizard(["/home/me/other"], cursor_cwd: "/home/me/other")

    # Act
    on_name = walk(wizard)

    # Assert
    assert {:done, %{cwd: "/home/me/other"}} = NewSessionWizard.accept(on_name)
  end

  test "typing filters known directories fuzzily and resets the selection" do
    # Arrange
    wizard = wizard(["/home/me/alpha", "/home/me/beta"])

    # Act
    filtered = wizard |> NewSessionWizard.move(1) |> NewSessionWizard.set_query("bet")

    # Assert
    assert [%{value: "/home/me/beta", kind: :project}] = NewSessionWizard.candidates(filtered)
    assert filtered.selected == 0
  end

  test "the walked directory list is used once loaded and stale roots are ignored" do
    # Arrange
    {wizard, root} = wizard() |> NewSessionWizard.request_index()

    # Act
    stale = NewSessionWizard.directories_loaded(wizard, "/elsewhere", ["nope"])
    loaded = NewSessionWizard.directories_loaded(wizard, root, ["code/sak"])

    # Assert
    assert root == @home
    assert stale.directories == []
    assert "/home/me/code/sak" in Enum.map(NewSessionWizard.candidates(loaded), & &1.value)
  end

  test "move stays within the candidates" do
    # Arrange
    wizard = wizard(["/home/me/alpha", "/home/me/beta"])

    # Act
    down = wizard |> NewSessionWizard.move(10)
    up = down |> NewSessionWizard.move(-10)

    # Assert
    assert {down.selected, up.selected} == {1, 0}
  end
end
