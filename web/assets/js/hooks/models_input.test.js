import assert from "node:assert/strict"
import test from "node:test"

import {actionFor} from "./models_input.js"

test("arrows move, enter picks and escape closes the models picker", () => {
  // Arrange
  const keys = ["ArrowDown", "ArrowUp", "Enter", "Escape", "a"]

  // Act
  const events = keys.map((key) => actionFor(key)?.event ?? null)

  // Assert
  assert.deepEqual(events, ["models_move", "models_move", "models_pick", "close_models", null])
})
