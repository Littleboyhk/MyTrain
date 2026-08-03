// Rendering tests for the solid-bar RailTrackPainter, plus the timing-verdict
// logic that replaced the track's colour states.
//
// This file previously asserted a two-rail tie ladder with three colour states.
// That design was reversed: the bar is one flat colour and the dual time columns
// carry the timing signal. The bar itself was then removed for a spell and these
// geometry tests deleted with it; both are restored — design.md section 2 has the
// sequence. The verdict tests below remain the important half: a wrong threshold
// silently mislabels a late train as on time.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_train/models/station_live_status.dart';
import 'package:my_train/theme/glass_theme.dart';
import 'package:my_train/widgets/rail_track/rail_track_layout.dart';
import 'package:my_train/widgets/rail_track/rail_track_painter.dart';

class RecordingCanvas implements Canvas {
  final List<({Rect rect, Color color})> rects = [];

  @override
  void drawRect(ui.Rect rect, Paint paint) =>
      rects.add((rect: rect, color: paint.color));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

RecordingCanvas paintSlice({
  double height = 110,
  double startY = 0,
  double? endY,
  GlassTheme theme = GlassTheme.dark,
}) {
  final canvas = RecordingCanvas();
  RailTrackPainter(
    barColor: theme.railBar,
    startY: startY,
    endY: endY,
  ).paint(canvas, Size(RailMetrics.gutterWidth, height));
  return canvas;
}

String hex(Color c) => '#'
    '${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}'
    '${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}'
    '${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}'
    .toUpperCase();

StationLegStatus leg({
  DateTime? scheduled,
  DateTime? actual,
  String rawDelay = '',
}) =>
    StationLegStatus(scheduled: scheduled, actual: actual, rawDelay: rawDelay);

DateTime at(int h, int m) => DateTime(2026, 7, 20, h, m);

void main() {
  group('solid bar geometry', () {
    test('one filled rect, centred, of barWidth', () {
      final c = paintSlice();
      expect(c.rects.length, 1,
          reason: 'the bar is a single rect, not a ladder');

      final r = c.rects.single.rect;
      expect(r.width, RailMetrics.barWidth);
      expect(r.center.dx, RailMetrics.gutterWidth / 2);
      expect(r.top, 0);
      expect(r.bottom, 110);
    });

    test('consecutive slices abut exactly, so the bar reads continuous', () {
      // Row A occupies 0..90 in its own space, row B starts at its top.
      final a = paintSlice(height: 90).rects.single.rect;
      final b = paintSlice(height: 70).rects.single.rect;
      expect(a.bottom, 90);
      expect(b.top, 0, reason: 'no inset, or a seam appears at every boundary');
    });

    test('the origin and terminus stop the bar at the dot', () {
      final first =
          paintSlice(startY: RailMetrics.pipCenterY).rects.single.rect;
      expect(first.top, RailMetrics.pipCenterY);

      final last = paintSlice(endY: RailMetrics.pipCenterY).rects.single.rect;
      expect(last.bottom, RailMetrics.pipCenterY);
    });

    test('a zero-height slice paints nothing rather than a hairline', () {
      expect(paintSlice(height: 0).rects, isEmpty);
      expect(paintSlice(startY: 40, endY: 40).rects, isEmpty);
    });

    test('one flat colour — no passed/active/upcoming variation', () {
      // The painter takes no state parameter at all. This test exists to fail
      // loudly if per-state colouring is ever reintroduced here rather than in
      // the time columns.
      final colour = paintSlice().rects.single.color;
      expect(hex(colour), hex(GlassTheme.dark.railBar));
      expect(hex(GlassTheme.dark.railBar), '#255C7E');
      expect(hex(GlassTheme.light.railBar), '#2F6E92');
    });

    test('dots are lighter than the bar in dark, darker in light', () {
      double lum(Color c) => 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
      expect(lum(GlassTheme.dark.railDot),
          greaterThan(lum(GlassTheme.dark.railBar)));
      expect(lum(GlassTheme.light.railDot),
          lessThan(lum(GlassTheme.light.railBar)));
    });
  });

  group('the 5-minute threshold', () {
    test('the constant is 5, and it is the boundary', () {
      expect(kDelayThresholdMinutes, 5);
    });

    test('4 minutes late is still green, 5 is red', () {
      // The exact boundary. Off-by-one here mislabels trains either way.
      final four = leg(scheduled: at(10, 0), actual: at(10, 4));
      final five = leg(scheduled: at(10, 0), actual: at(10, 5));

      expect(verdictFor(four, actualObserved: true), TimingVerdict.onTime);
      expect(verdictFor(five, actualObserved: true), TimingVerdict.delayed);
    });

    test('early and exactly on time are green', () {
      expect(
        verdictFor(leg(scheduled: at(10, 0), actual: at(10, 0)),
            actualObserved: true),
        TimingVerdict.onTime,
      );
      expect(
        verdictFor(leg(scheduled: at(10, 0), actual: at(9, 52)),
            actualObserved: true),
        TimingVerdict.onTime,
      );
    });

    test('a big delay is red', () {
      expect(
        verdictFor(leg(scheduled: at(10, 0), actual: at(11, 17)),
            actualObserved: true),
        TimingVerdict.delayed,
      );
    });

    test('computed times win over a contradicting label', () {
      // The colour must never contradict the two numbers printed beside it, so
      // the times are authoritative whenever both parse.
      final contradiction = leg(
        scheduled: at(10, 0),
        actual: at(10, 30),
        rawDelay: 'On Time',
      );
      expect(verdictFor(contradiction, actualObserved: true),
          TimingVerdict.delayed);
    });

    test('the label is the fallback when the actual will not parse', () {
      expect(
        verdictFor(leg(scheduled: at(10, 0), rawDelay: '15 Min Late'),
            actualObserved: true),
        TimingVerdict.delayed,
      );
      expect(
        verdictFor(leg(scheduled: at(10, 0), rawDelay: 'On Time'),
            actualObserved: true),
        TimingVerdict.onTime,
      );
      expect(
        verdictFor(leg(scheduled: at(10, 0), rawDelay: '3 Min Late'),
            actualObserved: true),
        TimingVerdict.onTime,
        reason: 'the threshold applies to the label path too',
      );
    });

    test('nothing to go on yields unknown, not a green guess', () {
      expect(verdictFor(leg(scheduled: at(10, 0)), actualObserved: true),
          TimingVerdict.unknown);
      expect(verdictFor(const StationLegStatus(), actualObserved: true),
          TimingVerdict.unknown);
    });

    test('an overnight crossing is not read as 23 hours late', () {
      // 23:50 scheduled, 00:05 actual the next day: 15 min late, not -1425.
      final overnight = StationLegStatus(
        scheduled: DateTime(2026, 7, 20, 23, 50),
        actual: DateTime(2026, 7, 21, 0, 5),
      );
      expect(overnight.delayMinutes, 15);
      expect(verdictFor(overnight, actualObserved: true),
          TimingVerdict.delayed);
    });
  });

  group('upcoming stations stay silent (constraint D2b)', () {
    test('an unobserved actual is never given a verdict', () {
      // Even with a perfectly parseable pair, an upcoming station gets no
      // colour — RailKit does not document what `actual` means before arrival.
      final looksOnTime = leg(scheduled: at(10, 0), actual: at(10, 0));
      expect(verdictFor(looksOnTime, actualObserved: false),
          TimingVerdict.unknown);

      final looksLate = leg(scheduled: at(10, 0), actual: at(10, 40));
      expect(verdictFor(looksLate, actualObserved: false),
          TimingVerdict.unknown);
    });

    test('only passed and current count as observed', () {
      expect(StationLiveStage.passed.actualIsObserved, isTrue);
      expect(StationLiveStage.current.actualIsObserved, isTrue);
      expect(StationLiveStage.upcoming.actualIsObserved, isFalse);
      expect(StationLiveStage.unreported.actualIsObserved, isFalse);
    });

    test('an unreported station cannot show an actual', () {
      const s = StationLiveStatus.unreported('ABCD');
      expect(s.canShowActual, isFalse);
      expect(s.stage, StationLiveStage.unreported);
    });
  });

  group('delay label parsing', () {
    test('reads the minute count out of RailKit prose', () {
      expect(leg(rawDelay: '15 Min Late').delayMinutesFromLabel, 15);
      expect(leg(rawDelay: '1 Min Late').delayMinutesFromLabel, 1);
      expect(leg(rawDelay: '120 Min Late').delayMinutesFromLabel, 120);
    });

    test('On Time is zero, not null', () {
      expect(leg(rawDelay: 'On Time').delayMinutesFromLabel, 0);
      expect(leg(rawDelay: 'on time').delayMinutesFromLabel, 0);
    });

    test('empty and unparseable yield null so the caller can stay silent', () {
      expect(leg(rawDelay: '').delayMinutesFromLabel, isNull);
      expect(leg(rawDelay: 'Rescheduled').delayMinutesFromLabel, isNull);
    });
  });
}
