import assert from "node:assert/strict"
import {test} from "node:test"
import {isNearBottom} from "./chat_scroll.js"

test("isNearBottom uses an 80px threshold", () => {
  // Arrange
  const near = {scrollHeight: 1000, scrollTop: 520, clientHeight: 400}
  const far = {scrollHeight: 1000, scrollTop: 400, clientHeight: 400}

  // Act
  const results = [isNearBottom(near), isNearBottom(far)]

  // Assert
  assert.deepEqual(results, [true, false])
})
