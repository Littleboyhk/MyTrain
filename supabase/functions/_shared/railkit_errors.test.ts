// Upstream 400s are not all the same thing.
//
// Every message below was returned verbatim by RailKit's getAvailability between
// 00:10 and 00:25 IST on 2026-08-08, while trackTrain kept working normally.
// Availability and PNR go through IRCTC's live booking system, which has a
// nightly maintenance window and is flaky around it; live tracking does not.
//
// All of them used to arrive as `validation`, which the app documents as "bad PNR
// / train number / date" — so an outage was reported to the user as their own
// mistake, with no suggestion that retrying would help.

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  classify400,
  railkitMonthlyLimit,
  railkitWarnAt,
  resetMonthlyLimitCacheForTest,
} from "./railkit.ts";

Deno.test("transient booking-host refusals are upstream_unavailable", async (t) => {
  const observed = [
    "Sorry for the inconvenience. Booking will be very slow or not accessible " +
    "between 11:45 PM and 00:15 AM, Please try after sometime",
    "Unable to perform Transaction. Please try later.",
    "Unable to process your request",
    "Something went wrong while fetching availability.",
  ];

  for (const msg of observed) {
    await t.step(msg.slice(0, 52), () => {
      assertEquals(classify400(msg), "upstream_unavailable");
    });
  }
});

Deno.test("genuine rejections stay validation", async (t) => {
  // "Date outside Tatkal ARP" is the observed example: correct, actionable, and
  // retrying it unchanged can never succeed. Telling the user to try again later
  // would loop them forever.
  const observed = [
    "Date outside Tatkal ARP",
    "Invalid train number",
    "Station code not found",
    "Train does not exist",
    "date must be YYYY-MM-DD, malformed input",
  ];

  for (const msg of observed) {
    await t.step(msg.slice(0, 52), () => {
      assertEquals(classify400(msg), "validation");
    });
  }
});

Deno.test("bad input wins over a polite retry suffix", () => {
  // The ordering that makes this work: BAD_INPUT patterns are tested first, so a
  // real rejection carrying "please try again" is not mistaken for an outage.
  assertEquals(
    classify400("Invalid station code, please try again"),
    "validation",
  );
  assertEquals(
    classify400("Date outside Tatkal ARP. Please try later."),
    "validation",
  );
});

Deno.test("an unrecognised 400 keeps the old behaviour", () => {
  // Defaults to validation on purpose. A novel outage phrasing is a missed
  // improvement; a novel domain rejection marked retryable would loop the user on
  // input that can never succeed. Add patterns as they are observed rather than
  // inverting this default.
  assertEquals(classify400("Some entirely new message"), "validation");
  assertEquals(classify400(""), "validation");
});

Deno.test("matching is case-insensitive", () => {
  assertEquals(
    classify400("UNABLE TO PERFORM TRANSACTION. PLEASE TRY LATER."),
    "upstream_unavailable",
  );
  assertEquals(classify400("INVALID TRAIN NUMBER"), "validation");
});

// ---------------------------------------------------------------------------
// The monthly budget, read lazily.
// ---------------------------------------------------------------------------
//
// This used to be `export const RAILKIT_MONTHLY_LIMIT = monthlyLimitFromEnv()`,
// evaluated at module scope — so importing this file to test `classify400` threw
// `NotCapable: Requires env access` before any assertion ran. The tests above now
// run with no permission flags at all, which is the point of the change.

Deno.test("the budget defaults to the Enterprise allowance", () => {
  // The bug this replaced: a hardcoded 50 (the free-tier figure) capped live
  // tracking at 50 requests a month on a 10,000-request account, and reported it
  // as "Monthly RailKit request budget reached" as though the upstream refused.
  resetMonthlyLimitCacheForTest();
  Deno.env.delete("RAILKIT_MONTHLY_LIMIT");
  assertEquals(railkitMonthlyLimit(), 10_000);
  assertEquals(railkitWarnAt(), 9_000);
});

Deno.test("the secret overrides the default, so a plan change needs no deploy", () => {
  resetMonthlyLimitCacheForTest();
  Deno.env.set("RAILKIT_MONTHLY_LIMIT", "30000");
  assertEquals(railkitMonthlyLimit(), 30_000);
  assertEquals(railkitWarnAt(), 27_000);
  resetMonthlyLimitCacheForTest();
  Deno.env.delete("RAILKIT_MONTHLY_LIMIT");
});

Deno.test("a nonsense secret falls back rather than disabling the guard", () => {
  // Zero or negative would switch the budget guard off entirely, which is worse
  // than ignoring the value.
  for (const bad of ["nonsense", "0", "-5", ""]) {
    resetMonthlyLimitCacheForTest();
    Deno.env.set("RAILKIT_MONTHLY_LIMIT", bad);
    assertEquals(railkitMonthlyLimit(), 10_000, `accepted "${bad}"`);
  }
  resetMonthlyLimitCacheForTest();
  Deno.env.delete("RAILKIT_MONTHLY_LIMIT");
});

Deno.test("the warn threshold tracks the limit instead of being a second constant", () => {
  // 45-next-to-50 is how the old pair drifted: the limit moved and the threshold
  // did not.
  resetMonthlyLimitCacheForTest();
  Deno.env.set("RAILKIT_MONTHLY_LIMIT", "100");
  assertEquals(railkitWarnAt(), 90);
  resetMonthlyLimitCacheForTest();
  Deno.env.delete("RAILKIT_MONTHLY_LIMIT");
});
