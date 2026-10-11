import assert from "node:assert/strict"
import test from "node:test"

import {fieldDelta, wantsRun} from "./skill_form.js"

test("square brackets move between fields and every other key is left to the input", () => {
  // Arrange
  const keys = ["[", "]", "a", "Enter", "Tab"]

  // Act
  const deltas = keys.map((key) => fieldDelta({key}))

  // Assert
  assert.deepEqual(deltas, [-1, 1, 0, 0, 0])
})

test("brackets with a modifier are not field switches", () => {
  assert.equal(fieldDelta({key: "[", ctrlKey: true}), 0)
  assert.equal(fieldDelta({key: "]", metaKey: true}), 0)
  assert.equal(fieldDelta({key: "]", altKey: true}), 0)
})

test("only enter with control or command runs the skill straight away", () => {
  assert.equal(wantsRun({key: "Enter", ctrlKey: true}), true)
  assert.equal(wantsRun({key: "Enter", metaKey: true}), true)
  assert.equal(wantsRun({key: "Enter"}), false)
  assert.equal(wantsRun({key: "a", ctrlKey: true}), false)
})
