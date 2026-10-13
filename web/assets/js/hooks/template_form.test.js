import assert from "node:assert/strict"
import test from "node:test"

import {tabDelta, wantsInsert} from "./template_form.js"

test("tab moves forward, shift-tab moves back and every other key is left to the textarea", () => {
  // Arrange
  const events = [
    {key: "Tab"},
    {key: "Tab", shiftKey: true},
    {key: "a"},
    {key: "Enter"},
    {key: "[", shiftKey: false},
  ]

  // Act
  const deltas = events.map(tabDelta)

  // Assert
  assert.deepEqual(deltas, [1, -1, 0, 0, 0])
})

test("tab with control, command or alt is left to the browser", () => {
  assert.equal(tabDelta({key: "Tab", ctrlKey: true}), 0)
  assert.equal(tabDelta({key: "Tab", metaKey: true}), 0)
  assert.equal(tabDelta({key: "Tab", altKey: true}), 0)
})

test("only enter with control or command inserts the template", () => {
  assert.equal(wantsInsert({key: "Enter", ctrlKey: true}), true)
  assert.equal(wantsInsert({key: "Enter", metaKey: true}), true)
  assert.equal(wantsInsert({key: "Enter"}), false)
  assert.equal(wantsInsert({key: "a", ctrlKey: true}), false)
})
