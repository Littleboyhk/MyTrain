import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pnr_status.dart';
import '../models/train_summary.dart';
import 'railkit_mappers.dart';
import 'railkit_service.dart';
import 'rapidapi_service.dart';
import 'train_repository.dart';

/// Real PNR lookup service backed by RapidAPI IRCTC.
class PnrService {
  const PnrService();

  static const String sampleConfirmed = '2451087345';
  static const String sampleWaitlisted = '8730561299';
  static const String sampleMixed = '4519023876';

  /// Featured samples surfaced as quick-fill chips on the input screen.
  static const List<({String pnr, String label})> samples = [
    (pnr: sampleConfirmed, label: 'Confirmed'),
    (pnr: sampleWaitlisted, label: 'Waitlisted'),
    (pnr: sampleMixed, label: 'Mixed'),
  ];

  /// Catalog train for a demo PNR. These numbers are known-present in the
  /// verified catalog, so a miss is a programming error — we assert rather than
  /// substituting some other train's details.
  TrainSummary _demoTrain(String number) {
    final t = trainRepository.resolveNumber(number);
    assert(t != null, 'demo PNR references unknown train $number');
    return t!;
  }

  /// Look up a 10-digit PNR.
  ///
  /// Order: RailKit (via Supabase, cached + quota-tracked) → RapidAPI → sample.
  /// A RailKit quota error is rethrown so the screen can show "check back
  /// later" instead of falling back to sample data.
  Future<PnrResult?> lookup(String pnr) async {
    const railkit = RailKitService();
    if (railkit.isAvailable) {
      try {
        final res = await railkit.checkPnr(pnr);
        final parsed = pnrFromRailkit(res.data, pnr);
        if (parsed != null) return parsed;
      } on RailKitException catch (e) {
        if (e.isQuota) rethrow; // surface; do NOT fall back to mock
        debugPrint('[PnrService] RailKit note: $e');
      } catch (e) {
        debugPrint('[PnrService] RailKit unexpected: $e');
      }
    }

    try {
      final realResult = await rapidApiService.getPnrStatus(pnr);
      if (realResult != null) return realResult;
    } catch (e) {
      debugPrint('[PnrService] RapidAPI PNR lookup notice: $e');
    }

    // DATA INTEGRITY: only the three explicitly-advertised demo PNRs may return
    // canned data (they're surfaced as "sample" chips in the UI). Any OTHER pnr
    // returns null -> "PNR not found", because inventing a confirmed booking
    // for a real passenger's PNR is a trust-breaking bug.
    return switch (pnr) {
      sampleConfirmed => _confirmed(pnr),
      sampleWaitlisted => _waitlisted(pnr),
      sampleMixed => _mixed(pnr),
      _ => null,
    };
  }

  DateTime _daysFromNow(int days) {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(Duration(days: days));
  }

  // ---------------------------------------------------------------------------
  // Sample states
  // ---------------------------------------------------------------------------

  /// Fully confirmed — chart prepared, every passenger has a berth. Two of the
  /// three moved up from RAC / waitlist, showcasing the booking→current diff.
  PnrResult _confirmed(String pnr) {
    return PnrResult(
      pnr: pnr,
      train: _demoTrain('12951'),
      journeyDate: _daysFromNow(1),
      travelClass: '3A',
      boardingCode: 'BCT',
      chartStatus: ChartStatus.prepared,
      passengers: const [
        PnrPassenger(
          index: 1,
          booking: SeatAllocation.confirmed('B1', '34', 'LB'),
          current: SeatAllocation.confirmed('B1', '34', 'LB'),
        ),
        PnrPassenger(
          index: 2,
          booking: SeatAllocation.rac(5),
          current: SeatAllocation.confirmed('B2', '12', 'UB'),
        ),
        PnrPassenger(
          index: 3,
          booking: SeatAllocation.waitlist(3),
          current: SeatAllocation.confirmed('B4', '7', 'MB'),
        ),
      ],
    );
  }

  /// All still waitlisted — chart not yet prepared, positions have moved up.
  PnrResult _waitlisted(String pnr) {
    return PnrResult(
      pnr: pnr,
      train: _demoTrain('12621'),
      journeyDate: _daysFromNow(6),
      travelClass: 'SL',
      boardingCode: 'MAS',
      chartStatus: ChartStatus.notPrepared,
      passengers: const [
        PnrPassenger(
          index: 1,
          booking: SeatAllocation.waitlist(21),
          current: SeatAllocation.waitlist(8),
        ),
        PnrPassenger(
          index: 2,
          booking: SeatAllocation.waitlist(22),
          current: SeatAllocation.waitlist(9),
        ),
      ],
    );
  }

  /// A mix — one confirmed, one RAC, one still waitlisted. Chart prepared.
  PnrResult _mixed(String pnr) {
    return PnrResult(
      pnr: pnr,
      train: _demoTrain('12259'),
      journeyDate: _daysFromNow(2),
      travelClass: '2A',
      boardingCode: 'SDAH',
      chartStatus: ChartStatus.prepared,
      passengers: const [
        PnrPassenger(
          index: 1,
          booking: SeatAllocation.waitlist(9),
          current: SeatAllocation.confirmed('A1', '23', 'LB'),
        ),
        PnrPassenger(
          index: 2,
          booking: SeatAllocation.waitlist(10),
          current: SeatAllocation.rac(3),
        ),
        PnrPassenger(
          index: 3,
          booking: SeatAllocation.waitlist(11),
          current: SeatAllocation.waitlist(4),
        ),
      ],
    );
  }
}

/// Stateless singleton service.
final pnrServiceProvider = Provider<PnrService>((ref) => const PnrService());
