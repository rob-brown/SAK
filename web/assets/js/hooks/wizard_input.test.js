import assert from "node:assert/strict"
import test from "node:test"

import {actionFor} from "./wizard_input.js"

test("arrow keys move the selection by one in either direction", () => {
  assert.deepEqual(actionFor("ArrowDown"), {event: "wizard_move", payload: {delta: 1}})
  assert.deepEqual(actionFor("ArrowUp"), {event: "wizard_move", payload: {delta: -1}})
})

test("enter accepts and escape goes back", () => {
  assert.deepEqual(actionFor("Enter"), {event: "wizard_accept", payload: {}})
  assert.deepEqual(actionFor("Escape"), {event: "wizard_back", payload: {}})
})

test("typing keys are left alone so the input handles them natively", () => {
  for (const key of ["a", "Z", "1", " ", "Backspace", "ArrowLeft", "Tab", "constructor"]) {
    assert.equal(actionFor(key), null)
  }
})
