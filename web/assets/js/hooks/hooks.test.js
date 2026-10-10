import assert from "node:assert/strict"
import {test} from "node:test"
import {isNearBottom} from "./chat_scroll.js"
import {actionFor} from "./prompt_box.js"

test("enter submits, shift+enter does not", () => {
  // Arrange
  const enter = {key: "Enter", shiftKey: false, isComposing: false}
  const shiftEnter = {key: "Enter", shiftKey: true, isComposing: false}

  // Act
  const results = [actionFor(enter), actionFor(shiftEnter)]

  // Assert
  assert.deepEqual(results, ["submit", "none"])
})

test("enter while composing is ignored", () => {
  // Arrange
  const composing = {key: "Enter", shiftKey: false, isComposing: true}

  // Act
  const result = actionFor(composing)

  // Assert
  assert.equal(result, "none")
})

test("escape blurs the prompt", () => {
  // Arrange
  const escape = {key: "Escape", shiftKey: false, isComposing: false}

  // Act
  const result = actionFor(escape)

  // Assert
  assert.equal(result, "blur")
})

test("isNearBottom uses an 80px threshold", () => {
  // Arrange
  const near = {scrollHeight: 1000, scrollTop: 520, clientHeight: 400}
  const far = {scrollHeight: 1000, scrollTop: 400, clientHeight: 400}

  // Act
  const results = [isNearBottom(near), isNearBottom(far)]

  // Assert
  assert.deepEqual(results, [true, false])
})
