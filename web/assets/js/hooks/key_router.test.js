import assert from "node:assert/strict"
import test from "node:test"

import {isModalOpen, modalKeys} from "./key_router.js"

test("no modal is open when none of the flags are set", () => {
  assert.equal(isModalOpen({}), false)
  assert.equal(isModalOpen({helpOpen: "false", wizardOpen: "false", commandOpen: "false"}), false)
})

test("help, models, wizard, command, rename and delete confirmation each count as a modal", () => {
  for (const flag of ["helpOpen", "modelsOpen", "wizardOpen", "commandOpen", "renameOpen", "confirmOpen"]) {
    assert.equal(isModalOpen({[flag]: "true"}), true, flag)
  }
})

test("only the delete confirmation also forwards enter", () => {
  assert.deepEqual(modalKeys({helpOpen: "true"}), ["escape"])
  assert.deepEqual(modalKeys({renameOpen: "true"}), ["escape"])
  assert.deepEqual(modalKeys({confirmOpen: "true"}), ["escape", "enter"])
})
