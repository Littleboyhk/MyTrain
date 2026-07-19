import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/pnr_status.dart';
import 'train_repository.dart';

/// Mock PNR lookup service.
///
/// Returns canned data after a short delay so the UI can exercise its loading,
/// result and not-found states without a backend. Three featured sample PNRs
/// map to the three showcase states; any other valid 10-digit PNR is resolved
/// deterministically (sum of digits) so the demo stays predictable.
///
/// When wiring real data later, the client should call a Supabase **edge
/// function** (as the existing `train_status` layer does) with the *anon* key
/// only — the service-role key must never ship in the app.
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

  /// Look up [pnr] (assumed to already be 10 digits). Resolves to `null` for a
  /// not-found result. Simulates network latency with an 800ms delay.
  Future<PnrResult?> lookup(String pnr) async {
    await Future.delayed(const Duration(milliseconds: 800));

    switch (pnr) {
      case sampleConfirmed:
        return _confirmed(pnr);
      case sampleWaitlisted:
        return _waitlisted(pnr);
      case sampleMixed:
        return _mixed(pnr);
    }

    // Deterministic fallback for any other valid PNR: sum the digits, then map
    // mod 4 to a state. One bucket is reserved for a friendly not-found path.
    final sum = pnr.codeUnits.fold<int>(0, (total, unit) => total + (unit - 48));
    return switch (sum % 4) {
      0 => _confirmed(pnr),
      1 => _mixed(pnr),
      2 => _waitlisted(pnr),
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
      train: trainRepository.resolveNumber('12951'),
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
      train: trainRepository.resolveNumber('12621'),
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
      train: trainRepository.resolveNumber('12259'),
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
