import {test} from "node:test"
import assert from "node:assert/strict"
import {
  decide,
  normalizeLineEndings,
  lineCount,
  activeMentionStart,
  appendBlock,
  isCommandTrigger,
  queueFor,
  PASTE_LINE_THRESHOLD,
} from "./prompt_box.js"

const short = "one\ntwo\nthree\nfour" // 4 lines — at the threshold, not over it
const long = "one\ntwo\nthree\nfour\nfive" // 5 lines — over the threshold

test("normalizeLineEndings collapses CRLF and bare CR to LF", () => {
  assert.equal(normalizeLineEndings("a\r\nb\rc\nd"), "a\nb\nc\nd")
})

test("lineCount counts by \\n, matching PasteDraft's line_count/1", () => {
  assert.equal(lineCount("a\nb\nc"), 3)
  assert.equal(lineCount("a"), 1)
  assert.equal(lineCount(""), 1)
})

test("a paste at or under the threshold is a plain insert", () => {
  assert.equal(lineCount(short), PASTE_LINE_THRESHOLD)
  assert.deepEqual(decide(null, short, 0), {type: "insert"})
})

test("a paste over the threshold becomes a numbered placeholder", () => {
  const decision = decide(null, long, 0)
  assert.equal(decision.type, "placeholder")
  assert.equal(decision.label, "[Pasted text #1 5 lines]")
  assert.equal(decision.text, long)
  assert.equal(decision.number, 1)
})

test("a second long paste in the same draft gets #2, not another #1", () => {
  const decision = decide(null, long, 1)
  assert.equal(decision.label, "[Pasted text #2 5 lines]")
})

test("re-pasting the exact same content as the pending placeholder expands it", () => {
  const pending = {label: "[Pasted text #1 5 lines]", content: long}
  const decision = decide(pending, long, 1)
  assert.deepEqual(decision, {type: "expand", label: pending.label, text: long})
})

test("pasting different content while one is pending creates a new placeholder instead of expanding", () => {
  const pending = {label: "[Pasted text #1 5 lines]", content: long}
  const otherLong = "a\nb\nc\nd\ne\nf"
  const decision = decide(pending, otherLong, 1)
  assert.equal(decision.type, "placeholder")
  assert.equal(decision.label, "[Pasted text #2 6 lines]")
})

test("two different pastes with the same line count get distinct labels (paste count breaks the tie)", () => {
  const firstLabel = decide(null, "a\nb\nc\nd\ne", 0).label
  const secondLabel = decide(null, "x\ny\nz\nw\nv", 1).label
  assert.notEqual(firstLabel, secondLabel)
})

test("activeMentionStart finds the nearest @ before the cursor", () => {
  assert.equal(activeMentionStart("hello @foo", 10), 6)
  assert.equal(activeMentionStart("@", 1), 0)
})

test("activeMentionStart stops at whitespace between @ and the cursor", () => {
  assert.equal(activeMentionStart("@foo bar", 8), null)
})

test("activeMentionStart returns null with no @ before the cursor", () => {
  assert.equal(activeMentionStart("hello world", 11), null)
})

test("activeMentionStart tracks the most recent @, not an earlier one", () => {
  assert.equal(activeMentionStart("@one @two", 9), 5)
})

test("isCommandTrigger fires on a colon typed into an empty prompt", () => {
  assert.equal(isCommandTrigger(":"), true)
})

test("isCommandTrigger ignores a colon inside or after other text, and plain text", () => {
  assert.equal(isCommandTrigger("hello:"), false)
  assert.equal(isCommandTrigger(":)"), false)
  assert.equal(isCommandTrigger("clear"), false)
  assert.equal(isCommandTrigger(""), false)
})

const key = (name, modifiers = {}) => ({
  key: name,
  shiftKey: false,
  ctrlKey: false,
  altKey: false,
  metaKey: false,
  ...modifiers,
})

test("plain enter submits as a steer", () => {
  assert.equal(queueFor(key("Enter")), "steer")
})

test("alt+enter and ctrl+enter submit as a follow-up", () => {
  assert.equal(queueFor(key("Enter", {altKey: true})), "follow_up")
  assert.equal(queueFor(key("Enter", {ctrlKey: true})), "follow_up")
})

test("shift+enter is a newline, even combined with alt or ctrl", () => {
  assert.equal(queueFor(key("Enter", {shiftKey: true})), null)
  assert.equal(queueFor(key("Enter", {shiftKey: true, altKey: true})), null)
  assert.equal(queueFor(key("Enter", {shiftKey: true, ctrlKey: true})), null)
})

test("meta+enter is not a submit", () => {
  assert.equal(queueFor(key("Enter", {metaKey: true})), null)
  assert.equal(queueFor(key("Enter", {metaKey: true, altKey: true})), null)
})

test("keys other than enter are not a submit", () => {
  assert.equal(queueFor(key("a")), null)
  assert.equal(queueFor(key("a", {altKey: true})), null)
})

test("appendBlock replaces a blank message and separates it from existing text", () => {
  // Arrange
  const block = "<task>\nX\n</task>"

  // Act
  const results = [appendBlock("", block), appendBlock("  \n", block), appendBlock("fix this\n", block), appendBlock("keep", "")]

  // Assert
  assert.deepEqual(results, [block, block, `fix this\n\n${block}`, "keep"])
})
