# Known follow-ups

Items flagged during the data-fabrication / privacy review and deliberately
deferred. None are blocking; all are believed correct-but-fragile rather than
broken today.

Established patterns to follow when fixing the logging items:
`RapidApiService._redact` (masks 10-digit IDs, keeps last 3),
`if (!kDebugMode) return;` gate, and `_logShape` (logs key *names*, never values)
— all in `lib/data/rapidapi_service.dart`.

---

## 1. Empty-string `trainName` default in live status

**Where:** `lib/data/rapidapi_service.dart` — `RapidApiService.getLiveTrainStatus`
(the `/api/v3/getTrainLiveStatus` endpoint), in the returned `LiveTrainStatusData`:

```dart
trainName: (data['train_name'] ?? '').toString(),
```

**Why it matters:** same class of bug as the fabrication issues already fixed —
a missing or renamed provider field becomes an empty string that reads as a real
(blank) name rather than "unknown". `LiveTrainStatusData.trainName` is
non-nullable `String`, so callers cannot distinguish absent from empty.

**Suggested fix:** make `trainName` nullable and pass `null` when the field is
missing, letting the UI dash it — consistent with how the PNR/timetable
sentinels (`'--:--'`, `'—'`, fabricated `'Daily'`) were replaced with `null`.

---

## 2. Duplicate train-type inference — already drifting

**Where:**
- `lib/data/rapidapi_service.dart` — `_inferTrainType(String name, String rawType)`
- `lib/data/railkit_mappers.dart` — `_inferType(String name, [String? rawType])`

**Why it matters:** these are not merely at risk of drift, they have already
drifted:

| | rapidapi `_inferTrainType` | railkit `_inferType` |
| --- | --- | --- |
| `humsafar` | not matched | → `Humsafar` |
| `express` / `exp` | not matched | → `Express` |
| `' sf '` → `Superfast` | matched | not matched |
| fallback | `rawType` if non-empty, else `Express` | always `Express` |
| `rawType` | required | optional |

So the same train can be typed differently depending on which provider served
the request.

**Suggested fix:** extract one shared inference helper (superset of both match
lists, single fallback policy) and have both mappers call it. Worth a small
table-driven test over the union of keywords.

---

## 3. Unredacted RailKit PNR mapping-failure log

**Where:** `lib/data/railkit_mappers.dart`, in the `pnrFromRailkit` catch block:

```dart
debugPrint('[RailKit] PNR mapping failed: $e\n$st');
```

**Why it matters:** neither `kDebugMode`-gated nor redacted. A provider
exception raised while mapping a PNR response can embed the PNR, passenger
names, or seat/berth data in its message; the stack trace adds no diagnostic
value beyond the exception type here.

**Suggested fix:** gate on `kDebugMode`, run the message through a shared
redactor, and drop the raw stack trace (or log only `e.runtimeType`).

**Sibling logs in the same file** — same shape, lower sensitivity since they
carry no passenger data, but worth the same treatment if the redactor is made
shared: `search mapping failed`, `trainInfo mapping failed`, `platform lookup
failed`, `track mapping failed`.

---

## Goldens cannot verify contrast against MeshBackground

**Standing constraint, not a task.** Any text or icon placed on this app's
backgrounds needs a manual on-device check in **both** themes. Goldens will not
catch a contrast failure there.

Why: `MeshBackground` renders its base mesh under `flutter test`, but the blob
layer over it does not paint. The blobs are exactly what breaks contrast — light
draws violet/blue/pink at `blobOpacity: 0.70`, so over a blob the backdrop becomes
a saturated mid-tone. Dark is milder but not safe either, at 0.35 over black.

This was found the hard way: the Coach Position fallback note ("No berth layout
for …") shipped as an icon plus `g.textMuted` text with no surface behind it and
was **invisible on a real device**, while every golden showed it perfectly legible.
Two attempts to reproduce the backdrop in the harness both failed — a `ColoredBox`
behind the screen is covered by the opaque mesh base, and overriding
`GlassTheme.mesh` to the worst-case composite does not visibly tint the render.

Practical rule: put content on a glass surface with its own scrim rather than
directly on the mesh. A neutral, fairly opaque scrim (near-white on light,
near-black on dark) is safer than a hue tint, because a tint has to compete with
whichever blob is behind it. `_NoStandardLayout` and `_AccuracyBanner` in
`coach_position_screen.dart` are the reference implementations.

Worst-case backdrop colours, for anyone eyeballing a design:
`~#9E6FF1` on light, `~#312056` on dark.

---

## On hold — 2A berth grid

**Status:** deliberately not built. Do not add it without the sources below.

The Coach Position tap-into-coach grid ships for **SL and 3A only**
(`CoachBerthLayout.supported`). 2A is on hold for two independent reasons:

1. **The cycle does not tile the coach.** 2A appears to run a mod-6 cycle —
   Lower, Upper, Lower, Upper, Side Lower, Side Upper — with no middle berth. But
   2A is 52 berths on LHB and ~46 on ICF, and both are of the form 6k+4. That
   leaves an irregular tail of four with no side berths, and which berths fall in
   it depends on the build. Berth 43 is a Lower in a normal group on a 52-berth
   coach and sits in the tail on a 46-berth one. Since no provider field states
   the rake generation, the tail cannot be placed.

2. **The mod-6 rule is not sourced.** It currently rests only on a description of
   a competitor app's UI — weaker sourcing than anything else in this codebase.
   The published per-coach-type map at `etrain.info/page/seatmap/2A` is a raster
   image and was not read.

To revisit, both are needed: the numbering confirmed against RDSO/IR material or
that image, **and** the tail's position and composition pinned down for each
build. 1A (cabins and coupes) and 3E (83 berths, side-middle) remain out of scope
entirely — neither has a cycle that tiles anything.

Related, and worth remembering: this grid has no integrity guard. The PNR bay view
can test its derivation against the provider's own `berthType` and refuse on
disagreement; the Coach Position screen has no PNR, so the cycle is applied
unchecked. That is why the class gate there is narrower than it might otherwise
need to be.

---

## Also observed while logging the above (not part of the original review)

`RapidApiService.getLiveTrainStatus` has two `debugPrint` calls that are **not**
`kDebugMode`-gated: the full request URI, and a raw `$e` on failure. Lower
severity than the PNR path — a train number is not personal data — but it is the
same pattern that was closed elsewhere, so flagging for consistency.
