import assert from "node:assert/strict"
import test from "node:test"

import {isModalOpen, modalKeys} from "./key_router.js"

test("no modal is open when none of the flags are set", () => {
  assert.equal(isModalOpen({}), false)
  assert.equal(isModalOpen({helpOpen: "false", wizardOpen: "false", commandOpen: "false"}), false)
})

test("help, the wizard and the command bar each count as a modal", () => {
  assert.equal(isModalOpen({helpOpen: "true"}), true)
  assert.equal(isModalOpen({modelsOpen: "true"}), true)
  assert.equal(isModalOpen({wizardOpen: "true"}), true)
  assert.equal(isModalOpen({commandOpen: "true"}), true)
})

test("only escape is forwarded to the server while a modal is open", () => {
  assert.deepEqual(modalKeys({helpOpen: "true"}), ["escape"])
  assert.deepEqual(modalKeys({wizardOpen: "true"}), ["escape"])
  assert.deepEqual(modalKeys({commandOpen: "true"}), ["escape"])
})
