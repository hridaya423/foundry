import { test } from "node:test";
import assert from "node:assert/strict";
import { calculate } from "../app/foundry/calculate.ts";

test("a leading minus binds looser than a power", () => {
  assert.equal(calculate("-2^2"), "-4");
  assert.equal(calculate("(-2)^2"), "4");
  assert.equal(calculate("2^-2"), "0.25");
  assert.equal(calculate("3*-2"), "-6");
});

test("a percentage after plus or minus is a share of the left side", () => {
  assert.equal(calculate("100 + 10%"), "110");
  assert.equal(calculate("100 - 10%"), "90");
  assert.equal(calculate("200 * 10%"), "20");
  assert.equal(calculate("50%"), "0.5");
});

test("results are capped to a readable number of digits", () => {
  assert.equal(calculate("1/3"), "0.333333333333");
  assert.equal(calculate("0.1+0.2"), "0.3");
  assert.equal(calculate("10^300"), "1e+300");
  assert.equal(calculate("10^300*1.5"), "1.5e+300");
  assert.equal(calculate("1/10^9"), "1e-9");
  assert.equal(calculate("0*-5"), "0");
  assert.equal(calculate("1000*1000"), "1,000,000");
});

test("text that is not arithmetic is left alone", () => {
  assert.equal(calculate("clipboard"), null);
  assert.equal(calculate("24"), null);
  assert.equal(calculate("1/0"), null);
});
