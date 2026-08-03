import assert from "node:assert/strict";
import test from "node:test";
import { accountKeyForEmail } from "../app/account-identity";

test("uses one stable private key per signed-in account", async () => {
  const owner = await accountKeyForEmail(" Person@Example.com ");
  const sameOwner = await accountKeyForEmail("person@example.com");
  const anotherPerson = await accountKeyForEmail("another@example.com");

  assert.equal(owner, sameOwner);
  assert.notEqual(owner, anotherPerson);
  assert.match(owner ?? "", /^[a-f0-9]{64}$/);
  assert.equal(owner, "542d240129883c019e106e3b1b2d3f3cb3537c43c425364de8e951d5a3083345");
  assert.equal(await accountKeyForEmail("   "), null);
});
