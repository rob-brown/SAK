import {test} from "node:test"
import assert from "node:assert/strict"
import {actionFor} from "./command_input.js"

test("arrows move the selection by one in either direction", () => {
  assert.deepEqual(actionFor("ArrowDown"), {event: "command_move", payload: {delta: 1}})
  assert.deepEqual(actionFor("ArrowUp"), {event: "command_move", payload: {delta: -1}})
})

test("enter runs and escape closes", () => {
  assert.equal(actionFor("Enter").event, "command_run")
  assert.equal(actionFor("Escape").event, "command_close")
})

test("typing keys are left alone so the input handles them natively", () => {
  assert.equal(actionFor("a"), null)
  assert.equal(actionFor(":"), null)
})
