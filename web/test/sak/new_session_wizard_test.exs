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

    assert result ==
             {:done, %{cwd: "/home/me/default", persona: nil, model_id: "beta-model", name: ""}}
  end

  @personas [
    %{"name" => "default", "description" => "General coding assistant", "model" => nil},
    %{"name" => "builder", "description" => "Implements a plan", "model" => "beta-model"},
    %{"name" => "critic", "description" => "Reviews code", "model" => "not-offered"}
  ]

  test "the persona step comes after the directory with the default first and descriptions attached" do
    # Arrange
    wizard = wizard([], personas: @personas, models: @models, default_model: "alpha-model")

    # Act
    on_persona = walk(wizard)

    # Assert
    assert NewSessionWizard.step_count(wizard) == 4
    assert on_persona.step == :persona

    assert [
             %{value: "default", kind: :default, detail: "General coding assistant"},
             %{value: "builder", kind: :persona},
             %{value: "critic"}
           ] = NewSessionWizard.candidates(on_persona)
  end

  test "a persona with a model offered by the endpoint makes it the model default" do
    # Arrange
    on_persona =
      [] |> wizard(personas: @personas, models: @models, default_model: "alpha-model") |> walk()

    builder = on_persona |> NewSessionWizard.set_query("build")

    # Act
    on_model = walk(builder)
    result = on_model |> walk() |> NewSessionWizard.accept()

    # Assert
    assert [%{value: "beta-model", kind: :default} | _] = NewSessionWizard.candidates(on_model)
    assert {:done, %{persona: "builder", model_id: "beta-model"}} = result
  end

  test "a persona whose model the endpoint does not offer falls back to the gateway default" do
    # Arrange
    on_persona =
      [] |> wizard(personas: @personas, models: @models, default_model: "alpha-model") |> walk()

    # Act
    on_model = on_persona |> NewSessionWizard.set_query("crit") |> walk()

    # Assert
    assert [%{value: "alpha-model", kind: :default} | _] = NewSessionWizard.candidates(on_model)
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
