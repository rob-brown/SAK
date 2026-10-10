import assert from "node:assert/strict"
import {test} from "node:test"
import {isNearBottom} from "./chat_scroll.js"
import {actionFor as keyAction, isTextEntry} from "./key_router.js"
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

test("key router maps navigation keys", () => {
  // Arrange
  const press = (key, extra = {}) => keyAction({key, ctrlKey: false, metaKey: false, altKey: false, ...extra})

  // Act
  const results = [
    press("j"),
    press("k"),
    press("G"),
    press("g"),
    press("i"),
    press("n"),
    press("d", {ctrlKey: true}),
    press("u", {ctrlKey: true}),
  ]

  // Assert
  assert.deepEqual(results, [
    {type: "scroll", lines: 1},
    {type: "scroll", lines: -1},
    {type: "scroll-edge", edge: "bottom"},
    {type: "scroll-edge", edge: "top"},
    {type: "focus", target: "prompt-input"},
    {type: "focus", target: "new-session-cwd"},
    {type: "scroll-page", direction: 1},
    {type: "scroll-page", direction: -1},
  ])
})

test("key router ignores browser shortcuts and unknown keys", () => {
  // Arrange
  const press = (key, extra) => keyAction({key, ctrlKey: false, metaKey: false, altKey: false, ...extra})

  // Act
  const results = [press("j", {metaKey: true}), press("j", {altKey: true}), press("x"), press("r", {ctrlKey: true})]

  // Assert
  assert.deepEqual(results, Array(4).fill({type: "none"}))
})

test("text entry detection covers inputs, textareas and contenteditable", () => {
  // Arrange
  const input = {tagName: "INPUT", isContentEditable: false}
  const editable = {tagName: "DIV", isContentEditable: true}
  const body = {tagName: "BODY", isContentEditable: false}

  // Act
  const results = [isTextEntry(input), isTextEntry(editable), isTextEntry(body), isTextEntry(null)]

  // Assert
  assert.deepEqual(results, [true, true, false, false])
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
