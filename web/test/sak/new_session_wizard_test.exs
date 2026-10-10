defmodule Sak.NewSessionWizardTest do
  use ExUnit.Case, async: true

  alias Sak.NewSessionWizard

  @home "/home/me"

  defp wizard(projects \\ [], hints \\ []) do
    NewSessionWizard.new("/home/me/default", projects, [home: @home] ++ hints)
  end

  test "enter accepts the default directory" do
    # Arrange
    wizard = wizard()

    # Act
    result = NewSessionWizard.accept(wizard)

    # Assert
    assert result == {:done, "/home/me/default"}
  end

  test "the directory under the sessions cursor becomes the default" do
    # Arrange
    wizard = wizard(["/home/me/other"], cursor_cwd: "/home/me/other")

    # Act
    result = NewSessionWizard.accept(wizard)

    # Assert
    assert result == {:done, "/home/me/other"}
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
