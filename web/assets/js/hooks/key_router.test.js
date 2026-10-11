import assert from "node:assert/strict"
import test from "node:test"

import {chatScrolls, isModalOpen, modalKeys} from "./key_router.js"

test("no modal is open when none of the flags are set", () => {
  assert.equal(isModalOpen({}), false)
  assert.equal(isModalOpen({helpOpen: "false", wizardOpen: "false", commandOpen: "false"}), false)
})

test("help, models, wizard, command, rename and delete confirmation each count as a modal", () => {
  for (const flag of ["helpOpen", "modelsOpen", "wizardOpen", "commandOpen", "renameOpen", "confirmOpen"]) {
    assert.equal(isModalOpen({[flag]: "true"}), true, flag)
  }
})

test("only the delete confirmation also forwards enter", () => {
  assert.deepEqual(modalKeys({helpOpen: "true"}), ["escape"])
  assert.deepEqual(modalKeys({renameOpen: "true"}), ["escape"])
  assert.deepEqual(modalKeys({confirmOpen: "true"}), ["escape", "enter"])
})

test("a permission prompt is a modal that forwards the answer keys", () => {
  assert.equal(isModalOpen({permissionOpen: "true"}), true)
  assert.deepEqual(modalKeys({permissionOpen: "true"}), ["escape", "y", "a", "n"])
  assert.deepEqual(modalKeys({permissionOpen: "true", confirmOpen: "true"}), ["escape", "y", "a", "n"])
})

test("the permission mode picker is a modal that forwards navigation, enter and escape", () => {
  assert.equal(isModalOpen({modePickerOpen: "true"}), true)
  assert.deepEqual(modalKeys({modePickerOpen: "true"}), ["escape", "enter", "up", "down", "j", "k"])
})

test("the usage panel is a modal that only needs escape", () => {
  assert.equal(isModalOpen({usageOpen: "true"}), true)
  assert.deepEqual(modalKeys({usageOpen: "true"}), ["escape"])
})

test("the chat pane scrolls natively on the chat tab and hands keys to the server on the entries tab", () => {
  // Arrange
  const chat = {focusedPane: "chat_history", chatTab: "chat"}
  const entries = {focusedPane: "chat_history", chatTab: "entries"}
  const sessions = {focusedPane: "sessions_and_logs", chatTab: "chat"}
  const subagents = {focusedPane: "chat_history", chatTab: "subagents"}

  // Act
  const results = [chatScrolls(chat), chatScrolls(entries), chatScrolls(sessions), chatScrolls(subagents)]

  // Assert
  assert.deepEqual(results, [true, false, false, false])
})
