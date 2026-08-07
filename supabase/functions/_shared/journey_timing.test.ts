// Tests for the static-schedule timing gate that guards GPS-less coach reports.
//
// RUN WITH:  node --test supabase/functions/_shared/journey_timing.test.ts
//
// Node, not Deno. The functions under test live in `journey_match.ts`, which is
// pure TypeScript with zero imports and no Deno APIs — deliberately, per the note
// at the top of that file ("a pure function of (route, samples, now) so it can be
// tested without a database or a device"). Node 23+ strips types natively, so this
// needs no package.json, no node_modules and no install step. There is no Deno on
// the dev machine and no Deno test harness in this repo; this is the cheapest way
// to actually EXECUTE the rule rather than review it.
//
// WHAT MATTERS HERE. This gate hard-rejects, so a false positive silently refuses a
// real passenger's warning. The multi-day cases are the ones worth staring at:
// Indian long-distance trains routinely run past two calendar days, and a naive
// "journey_date must be today or yesterday" rule would refuse exactly the
// passengers who have had the longest to notice a problem.

import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  MAX_JOURNEY_AGE_DAYS_WITHOUT_SCHEDULE,
  POST_ARRIVAL_GRACE_HOURS,
  istDateString,
  journeyDateAgeDays,
  journeyStartEpochMs,
  journeyTimingVerdict,
  scheduledArrivalEpochMs,
  scheduledDepartureEpochMs,
  type RoutePoint,
} from "./journey_match.ts";

const HOUR = 3_600_000;
const DAY = 86_400_000;

/** IST midnight of a date, plus an offset in minutes. */
function ist(date: string, minutes = 0): number {
  return journeyStartEpochMs(date) + minutes * 60_000;
}

/** A minimal route with a timed origin and destination.
 *  [departMin] / [arriveMin] are minutes from journey-date IST midnight, so day
 *  offsets are expressed by going past 1440 exactly as the real builder does. */
function route(departMin: number | null, arriveMin: number | null): RoutePoint[] {
  return [
    {
      code: "ORG",
      name: "Origin",
      lat: 19.0,
      lng: 72.8,
      km: 0,
      arrivalMin: null,
      departureMin: departMin,
      isHalt: true,
    },
    {
      code: "DST",
      name: "Destination",
      lat: 28.6,
      lng: 77.2,
      km: 1384,
      arrivalMin: arriveMin,
      departureMin: null,
      isHalt: true,
    },
  ];
}

describe("istDateString", () => {
  it("uses the IST calendar day, not the UTC one", () => {
    // 20:30 UTC on the 7th is 02:00 IST on the 8th. Getting this wrong would
    // mislabel every journey for five and a half hours each night.
    assert.equal(istDateString(Date.parse("2026-08-07T20:30:00Z")), "2026-08-08");
    assert.equal(istDateString(Date.parse("2026-08-07T18:29:00Z")), "2026-08-07");
  });

  it("is exact at IST midnight", () => {
    assert.equal(istDateString(ist("2026-08-07")), "2026-08-07");
    assert.equal(istDateString(ist("2026-08-07") - 1), "2026-08-06");
  });
});

describe("journeyDateAgeDays", () => {
  const now = ist("2026-08-07", 15 * 60); // 15:00 IST on the 7th

  it("counts today as 0 and yesterday as 1", () => {
    assert.equal(journeyDateAgeDays("2026-08-07", now), 0);
    assert.equal(journeyDateAgeDays("2026-08-06", now), 1);
    assert.equal(journeyDateAgeDays("2026-08-04", now), 3);
  });

  it("goes negative for a future journey date", () => {
    assert.equal(journeyDateAgeDays("2026-08-08", now), -1);
  });

  it("is NaN for a date that is not a date", () => {
    assert.ok(Number.isNaN(journeyDateAgeDays("not-a-date", now)));
  });

  it("does not drift across a month or year boundary", () => {
    assert.equal(journeyDateAgeDays("2026-07-31", ist("2026-08-01", 60)), 1);
    assert.equal(journeyDateAgeDays("2025-12-31", ist("2026-01-01", 60)), 1);
  });
});

describe("schedule bounds from a route", () => {
  it("reads departure forward and arrival backward", () => {
    const r = route(17 * 60, 24 * 60 + 8 * 60); // dep 17:00 day 1, arr 08:00 day 2
    assert.equal(
      scheduledDepartureEpochMs(r, "2026-08-07"),
      ist("2026-08-07", 17 * 60),
    );
    assert.equal(
      scheduledArrivalEpochMs(r, "2026-08-07"),
      ist("2026-08-07", 32 * 60),
    );
  });

  it("returns null when the route carries no times at all", () => {
    const r = route(null, null);
    assert.equal(scheduledDepartureEpochMs(r, "2026-08-07"), null);
    assert.equal(scheduledArrivalEpochMs(r, "2026-08-07"), null);
  });

  it("falls back to the other time on a point that has only one", () => {
    // Origin with only an arrival, destination with only a departure.
    const r: RoutePoint[] = [
      { ...route(null, null)[0], arrivalMin: 600, departureMin: null },
      { ...route(null, null)[1], arrivalMin: null, departureMin: 900 },
    ];
    assert.equal(scheduledDepartureEpochMs(r, "2026-08-07"), ist("2026-08-07", 600));
    assert.equal(scheduledArrivalEpochMs(r, "2026-08-07"), ist("2026-08-07", 900));
  });
});

describe("journeyTimingVerdict — rejects", () => {
  it("refuses a journey date in the future", () => {
    const now = ist("2026-08-07", 15 * 60);
    const v = journeyTimingVerdict("2026-08-08", null, null, now);
    assert.equal(v.plausible, false);
    assert.equal(v.basis, "future_date");
  });

  it("refuses a train that has not departed — the yard case", () => {
    const now = ist("2026-08-07", 10 * 60); // 10:00
    const dep = ist("2026-08-07", 17 * 60); // departs 17:00
    const arr = ist("2026-08-07", 32 * 60);
    const v = journeyTimingVerdict("2026-08-07", dep, arr, now);
    assert.equal(v.plausible, false);
    assert.equal(v.basis, "not_departed");
  });

  it("refuses a journey that finished more than the grace period ago", () => {
    const arr = ist("2026-08-05", 8 * 60);
    const now = arr + (POST_ARRIVAL_GRACE_HOURS + 1) * HOUR;
    const v = journeyTimingVerdict(
      "2026-08-05",
      ist("2026-08-05", 60),
      arr,
      now,
    );
    assert.equal(v.plausible, false);
    assert.equal(v.basis, "journey_over");
  });

  it("refuses a stale date when the schedule offers no arrival", () => {
    const now = ist("2026-08-07", 12 * 60);
    const v = journeyTimingVerdict("2026-08-04", null, null, now);
    assert.equal(v.plausible, false);
    assert.equal(v.basis, "stale_date");
  });

  it("refuses a date that is not a date", () => {
    const v = journeyTimingVerdict("07-08-2026", null, null, Date.now());
    assert.equal(v.plausible, false);
    assert.equal(v.basis, "invalid_date");
  });

  it("always supplies a message a passenger can read", () => {
    const now = ist("2026-08-07", 12 * 60);
    for (const v of [
      journeyTimingVerdict("2026-08-09", null, null, now),
      journeyTimingVerdict("2026-08-04", null, null, now),
      journeyTimingVerdict("nope", null, null, now),
      journeyTimingVerdict("2026-08-07", ist("2026-08-07", 20 * 60), null, now),
    ]) {
      assert.equal(v.plausible, false);
      assert.ok(v.message.length > 0, `basis ${v.basis} had no message`);
      // No internals leaked into user-facing copy.
      assert.ok(!/journey_date|epoch|null/.test(v.message), v.message);
    }
  });
});

describe("journeyTimingVerdict — accepts", () => {
  it("accepts mid-journey", () => {
    const dep = ist("2026-08-07", 17 * 60);
    const arr = ist("2026-08-08", 8 * 60);
    const v = journeyTimingVerdict("2026-08-07", dep, arr, dep + 4 * HOUR);
    assert.equal(v.plausible, true);
    assert.equal(v.basis, "schedule");
    assert.equal(v.message, "");
  });

  it("accepts exactly at departure and exactly at the arrival cutoff", () => {
    const dep = ist("2026-08-07", 17 * 60);
    const arr = ist("2026-08-08", 8 * 60);
    assert.equal(journeyTimingVerdict("2026-08-07", dep, arr, dep).plausible, true);
    const cutoff = arr + POST_ARRIVAL_GRACE_HOURS * HOUR;
    assert.equal(journeyTimingVerdict("2026-08-07", dep, arr, cutoff).plausible, true);
    assert.equal(
      journeyTimingVerdict("2026-08-07", dep, arr, cutoff + 1).plausible,
      false,
    );
  });

  it("accepts a late-running train inside the grace period", () => {
    const dep = ist("2026-08-06", 17 * 60);
    const arr = ist("2026-08-07", 8 * 60);
    // Six hours behind schedule, still on board. This is the common case, not an
    // edge case.
    const v = journeyTimingVerdict("2026-08-06", dep, arr, arr + 6 * HOUR);
    assert.equal(v.plausible, true);
  });

  it("accepts today or yesterday with no schedule at all", () => {
    const now = ist("2026-08-07", 12 * 60);
    assert.equal(
      journeyTimingVerdict("2026-08-07", null, null, now).basis,
      "date_only",
    );
    assert.equal(
      journeyTimingVerdict("2026-08-06", null, null, now).plausible,
      true,
    );
    // One day past the fallback bound.
    assert.equal(
      journeyTimingVerdict("2026-08-05", null, null, now).plausible,
      false,
    );
    assert.equal(MAX_JOURNEY_AGE_DAYS_WITHOUT_SCHEDULE, 1);
  });

  it("accepts with only a departure known, if the date is not stale", () => {
    const now = ist("2026-08-07", 12 * 60);
    const v = journeyTimingVerdict("2026-08-07", ist("2026-08-07", 60), null, now);
    assert.equal(v.plausible, true);
    assert.equal(v.basis, "schedule_partial");
  });

  // -------------------------------------------------------------------------
  // The cases a naive "today or yesterday" rule would have broken.
  // -------------------------------------------------------------------------
  it("accepts day 4 of 22503 Vivek Express", () => {
    // Roughly 82 hours end to end, the longest scheduled run on IR.
    const dep = ist("2026-08-04", 23 * 60 + 55);
    const arr = dep + 82 * HOUR;
    const now = dep + 70 * HOUR; // still on board, journey_date is 3 days old
    assert.equal(journeyDateAgeDays("2026-08-04", now), 3);

    const v = journeyTimingVerdict("2026-08-04", dep, arr, now);
    assert.equal(v.plausible, true, "a day-4 passenger must still be able to report");
    assert.equal(v.basis, "schedule");
  });

  it("accepts day 3 of a Himsagar-length run", () => {
    const dep = ist("2026-08-05", 14 * 60);
    const arr = dep + 71 * HOUR;
    const now = dep + 60 * HOUR; // 02:00 IST on the 8th
    assert.equal(journeyDateAgeDays("2026-08-05", now), 3);
    assert.equal(journeyTimingVerdict("2026-08-05", dep, arr, now).plausible, true);
  });

  it("still refuses a multi-day train once it has actually arrived", () => {
    const dep = ist("2026-08-01", 14 * 60);
    const arr = dep + 71 * HOUR;
    const now = arr + (POST_ARRIVAL_GRACE_HOURS + 2) * HOUR;
    // The schedule bound does the work the calendar rule cannot: long journeys are
    // allowed to be old, finished ones are not.
    const v = journeyTimingVerdict("2026-08-01", dep, arr, now);
    assert.equal(v.plausible, false);
    assert.equal(v.basis, "journey_over");
  });
});

describe("journeyTimingVerdict — boundary arithmetic", () => {
  it("treats a journey starting just before IST midnight correctly", () => {
    // Departs 23:50 on the 7th, arrives 06:00 on the 9th (minutes past 1440).
    const dep = ist("2026-08-07", 23 * 60 + 50);
    const arr = ist("2026-08-07", 24 * 60 + 6 * 60);
    // 00:30 IST on the 8th: 40 minutes into the journey, and a UTC-based day
    // calculation would have called this "tomorrow's train".
    const now = ist("2026-08-08", 30);
    const v = journeyTimingVerdict("2026-08-07", dep, arr, now);
    assert.equal(v.plausible, true);
    assert.equal(v.basis, "schedule");
  });

  it("is stable across a year boundary", () => {
    const dep = ist("2025-12-31", 22 * 60);
    const arr = ist("2025-12-31", 24 * 60 + 10 * 60);
    const now = ist("2026-01-01", 2 * 60);
    assert.equal(journeyTimingVerdict("2025-12-31", dep, arr, now).plausible, true);
  });

  it("the grace period is the documented 12 hours", () => {
    assert.equal(POST_ARRIVAL_GRACE_HOURS, 12);
  });
});
