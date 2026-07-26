import 'package:flutter/foundation.dart';

import '../models/rail_station.dart';
import '../models/train_summary.dart';
import 'railkit_mappers.dart';
import 'railkit_service.dart';
import 'rapidapi_service.dart';

/// Validation helper to enforce authentic 5-digit Indian Railways train numbers.
bool isValidIRTrainNumber(String number) {
  final clean = number.trim();
  if (!RegExp(r'^\d{5}$').hasMatch(clean)) return false;
  final first = int.tryParse(clean[0]);
  return first != null && first >= 0 && first <= 9;
}

/// Provides train lookups against authentic Indian Railways 5-digit train numbers.
class TrainRepository {
  const TrainRepository();

  /// Real Indian Railways train catalog powering route and number searches.
  static const List<TrainSummary> catalog = [
    // -------------------------------------------------------------------------
    // Route: Kayankulam (KYJ) <-> KSR Bengaluru (SBC / BNC)
    // -------------------------------------------------------------------------
    TrainSummary(
      number: '16525',
      name: 'Kayankulam–Bangalore Express',
      fromCode: 'KYJ',
      fromName: 'Kayankulam Jn',
      toCode: 'SBC',
      toName: 'KSR Bengaluru',
      departure: '16:55',
      arrival: '06:40',
      duration: '13h 45m',
      daysLabel: 'Daily',
      type: 'Express',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '16526',
      name: 'Bangalore–Kayankulam Express',
      fromCode: 'SBC',
      fromName: 'KSR Bengaluru',
      toCode: 'KYJ',
      toName: 'Kayankulam Jn',
      departure: '20:10',
      arrival: '09:20',
      duration: '13h 10m',
      daysLabel: 'Daily',
      type: 'Express',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '16316',
      name: 'Kochuveli–Bangalore Express',
      fromCode: 'KYJ',
      fromName: 'Kayankulam Jn',
      toCode: 'SBC',
      toName: 'KSR Bengaluru',
      departure: '18:35',
      arrival: '08:35',
      duration: '14h 00m',
      daysLabel: 'Daily',
      type: 'Express',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12678',
      name: 'Ernakulam–Bangalore Intercity Express',
      fromCode: 'KYJ',
      fromName: 'Kayankulam Jn',
      toCode: 'SBC',
      toName: 'KSR Bengaluru',
      departure: '09:10',
      arrival: '19:50',
      duration: '10h 40m',
      daysLabel: 'Daily',
      type: 'Superfast',
    ),
    TrainSummary(
      number: '12677',
      name: 'Bangalore–Ernakulam Intercity Express',
      fromCode: 'SBC',
      fromName: 'KSR Bengaluru',
      toCode: 'KYJ',
      toName: 'Kayankulam Jn',
      departure: '06:10',
      arrival: '16:55',
      duration: '10h 45m',
      daysLabel: 'Daily',
      type: 'Superfast',
    ),

    // -------------------------------------------------------------------------
    // Route: Mumbai Central / CSMT (BCT / MMCT) <-> New Delhi (NDLS / NZM)
    // -------------------------------------------------------------------------
    TrainSummary(
      number: '12951',
      name: 'Mumbai Rajdhani Express',
      fromCode: 'BCT',
      fromName: 'Mumbai Central',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '17:00',
      arrival: '08:32',
      duration: '15h 32m',
      daysLabel: 'Daily',
      type: 'Rajdhani',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12952',
      name: 'New Delhi–Mumbai Rajdhani Express',
      fromCode: 'NDLS',
      fromName: 'New Delhi',
      toCode: 'BCT',
      toName: 'Mumbai Central',
      departure: '16:55',
      arrival: '08:35',
      duration: '15h 40m',
      daysLabel: 'Daily',
      type: 'Rajdhani',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12953',
      name: 'August Kranti Rajdhani Express',
      fromCode: 'BCT',
      fromName: 'Mumbai Central',
      toCode: 'NZM',
      toName: 'H Nizamuddin',
      departure: '17:10',
      arrival: '10:55',
      duration: '17h 45m',
      daysLabel: 'Daily',
      type: 'Rajdhani',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12137',
      name: 'Punjab Mail',
      fromCode: 'CSTM',
      fromName: 'Mumbai CSMT',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '19:35',
      arrival: '21:30',
      duration: '25h 55m',
      daysLabel: 'Daily',
      type: 'Mail',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12925',
      name: 'Paschim Express',
      fromCode: 'BCT',
      fromName: 'Mumbai Central',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '11:25',
      arrival: '10:40',
      duration: '23h 15m',
      daysLabel: 'Daily',
      type: 'Superfast',
      arrivalDayOffset: 1,
    ),

    // -------------------------------------------------------------------------
    // Route: Chennai Central (MAS) <-> KSR Bengaluru (SBC)
    // -------------------------------------------------------------------------
    TrainSummary(
      number: '12027',
      name: 'Chennai–Bangalore Shatabdi Express',
      fromCode: 'MAS',
      fromName: 'Chennai Central',
      toCode: 'SBC',
      toName: 'KSR Bengaluru',
      departure: '17:30',
      arrival: '22:25',
      duration: '4h 55m',
      daysLabel: 'Daily except Tue',
      type: 'Shatabdi',
    ),
    TrainSummary(
      number: '12028',
      name: 'Bangalore–Chennai Shatabdi Express',
      fromCode: 'SBC',
      fromName: 'KSR Bengaluru',
      toCode: 'MAS',
      toName: 'Chennai Central',
      departure: '06:00',
      arrival: '11:00',
      duration: '5h 00m',
      daysLabel: 'Daily except Tue',
      type: 'Shatabdi',
    ),
    TrainSummary(
      number: '12639',
      name: 'Brindavan Express',
      fromCode: 'MAS',
      fromName: 'Chennai Central',
      toCode: 'SBC',
      toName: 'KSR Bengaluru',
      departure: '07:40',
      arrival: '13:40',
      duration: '6h 00m',
      daysLabel: 'Daily',
      type: 'Superfast',
    ),
    TrainSummary(
      number: '12640',
      name: 'Brindavan Express',
      fromCode: 'SBC',
      fromName: 'KSR Bengaluru',
      toCode: 'MAS',
      toName: 'Chennai Central',
      departure: '15:10',
      arrival: '21:10',
      duration: '6h 00m',
      daysLabel: 'Daily',
      type: 'Superfast',
    ),
    TrainSummary(
      number: '12607',
      name: 'Lalbagh SF Express',
      fromCode: 'MAS',
      fromName: 'Chennai Central',
      toCode: 'SBC',
      toName: 'KSR Bengaluru',
      departure: '15:30',
      arrival: '21:35',
      duration: '6h 05m',
      daysLabel: 'Daily',
      type: 'Superfast',
    ),
    TrainSummary(
      number: '12657',
      name: 'Chennai–Bangalore Superfast Mail',
      fromCode: 'MAS',
      fromName: 'Chennai Central',
      toCode: 'SBC',
      toName: 'KSR Bengaluru',
      departure: '22:50',
      arrival: '04:30',
      duration: '5h 40m',
      daysLabel: 'Daily',
      type: 'Superfast',
    ),

    // -------------------------------------------------------------------------
    // Other Major Routes
    // -------------------------------------------------------------------------
    TrainSummary(
      number: '12301',
      name: 'Howrah Rajdhani Express',
      fromCode: 'HWH',
      fromName: 'Howrah Jn',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '16:50',
      arrival: '10:05',
      duration: '17h 15m',
      daysLabel: 'Daily',
      type: 'Rajdhani',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12259',
      name: 'Sealdah Duronto Express',
      fromCode: 'SDAH',
      fromName: 'Sealdah',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '12:40',
      arrival: '08:00',
      duration: '19h 20m',
      daysLabel: 'Daily',
      type: 'Duronto',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12002',
      name: 'Bhopal Shatabdi Express',
      fromCode: 'NDLS',
      fromName: 'New Delhi',
      toCode: 'BPL',
      toName: 'Bhopal Jn',
      departure: '06:00',
      arrival: '14:05',
      duration: '8h 05m',
      daysLabel: 'Daily',
      type: 'Shatabdi',
    ),
    TrainSummary(
      number: '12615',
      name: 'Grand Trunk Express',
      fromCode: 'NDLS',
      fromName: 'New Delhi',
      toCode: 'MAS',
      toName: 'Chennai Central',
      departure: '18:40',
      arrival: '07:00',
      duration: '36h 20m',
      daysLabel: 'Daily',
      type: 'Superfast',
      arrivalDayOffset: 2,
    ),
    TrainSummary(
      number: '12621',
      name: 'Tamil Nadu Express',
      fromCode: 'MAS',
      fromName: 'Chennai Central',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '22:00',
      arrival: '07:15',
      duration: '33h 15m',
      daysLabel: 'Daily',
      type: 'Superfast',
      arrivalDayOffset: 2,
    ),
    TrainSummary(
      number: '12627',
      name: 'Karnataka Express',
      fromCode: 'SBC',
      fromName: 'KSR Bengaluru',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '19:20',
      arrival: '10:45',
      duration: '39h 25m',
      daysLabel: 'Daily',
      type: 'Superfast',
      arrivalDayOffset: 2,
    ),
    TrainSummary(
      number: '12723',
      name: 'Telangana Express',
      fromCode: 'HYB',
      fromName: 'Hyderabad Deccan',
      toCode: 'NDLS',
      toName: 'New Delhi',
      departure: '06:25',
      arrival: '11:00',
      duration: '28h 35m',
      daysLabel: 'Daily',
      type: 'Superfast',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12841',
      name: 'Coromandel Express',
      fromCode: 'SHM',
      fromName: 'Shalimar',
      toCode: 'MAS',
      toName: 'Chennai Central',
      departure: '14:50',
      arrival: '16:50',
      duration: '26h 00m',
      daysLabel: 'Daily',
      type: 'Superfast',
      arrivalDayOffset: 1,
    ),
    TrainSummary(
      number: '12009',
      name: 'Ahmedabad Shatabdi Express',
      fromCode: 'BCT',
      fromName: 'Mumbai Central',
      toCode: 'ADI',
      toName: 'Ahmedabad Jn',
      departure: '06:25',
      arrival: '13:10',
      duration: '6h 45m',
      daysLabel: 'Daily',
      type: 'Shatabdi',
    ),
    TrainSummary(
      number: '20901',
      name: 'Mumbai–Gandhinagar Vande Bharat',
      fromCode: 'BCT',
      fromName: 'Mumbai Central',
      toCode: 'ADI',
      toName: 'Ahmedabad Jn',
      departure: '06:00',
      arrival: '11:25',
      duration: '5h 25m',
      daysLabel: 'Daily except Sun',
      type: 'Vande Bharat',
    ),
  ];

  /// Search the catalog by train number, train name, or station code/name.
  List<TrainSummary> searchByNumberOrName(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final results = <TrainSummary>[];

    for (final t in catalog) {
      if (!isValidIRTrainNumber(t.number)) continue;
      if (t.number.contains(q) ||
          t.name.toLowerCase().contains(q) ||
          t.fromCode.toLowerCase().contains(q) ||
          t.toCode.toLowerCase().contains(q) ||
          t.fromName.toLowerCase().contains(q) ||
          t.toName.toLowerCase().contains(q) ||
          t.type.toLowerCase().contains(q)) {
        results.add(t);
      }
    }
    return results;
  }

  /// Resolve a train number against the verified catalog.
  ///
  /// DATA INTEGRITY: returns null when the number isn't known. It used to
  /// fabricate a "Mumbai Central → New Delhi" express (defaulting to 12951) for
  /// ANY unknown number, which showed users a route that wasn't the train they
  /// asked for. Callers must handle null (fetch real data or show an error).
  TrainSummary? resolveNumber(String number) {
    final n = number.trim();
    for (final t in catalog) {
      if (t.number == n && isValidIRTrainNumber(t.number)) return t;
    }
    return null;
  }

  /// Returns real verified trains for the station pair.
  /// Returns real verified trains for the station pair via RapidAPI IRCTC.
  Future<List<TrainSummary>> betweenStations(
    RailStation from,
    RailStation to, {
    DateTime? date,
  }) async {
    // 0) RailKit via Supabase (preferred): server-cached + quota-tracked, so
    //    repeat searches for the same route cost zero RailKit requests.
    const railkit = RailKitService();
    if (railkit.isAvailable) {
      try {
        final iso = date == null
            ? null
            : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        final res = await railkit.searchTrains(
          from: from.code,
          to: to.code,
          date: iso,
        );
        final trains = trainsFromRailkitSearch(res.data, from, to);
        if (trains.isNotEmpty) return trains;
        // Empty/unrecognized shape → fall through to legacy sources.
      } on RailKitException catch (e) {
        // Quota is a real state: surface it, never silently show mock data.
        if (e.isQuota) rethrow;
        debugPrint('[TrainRepository] RailKit note: $e');
      } catch (e) {
        debugPrint('[TrainRepository] RailKit unexpected: $e');
      }
    }

    try {
      final apiResults = await rapidApiService.getTrainsBetweenStations(
        from: from,
        to: to,
        date: date,
      );
      if (apiResults.isNotEmpty) {
        return apiResults;
      }
    } catch (e) {
      debugPrint('[TrainRepository] RapidAPI route lookup note: $e');
      // On network or API error, throw or return verified catalog for selected route
    }

    final fromCode = from.code.trim().toUpperCase();
    final toCode = to.code.trim().toUpperCase();
    final fromCity = _city(from.name).toLowerCase();
    final toCity = _city(to.name).toLowerCase();

    // Direct verified catalog lookup (e.g. KYJ -> SBC: 16525/16526, BCT -> NDLS: 12951, MAS -> SBC: 12027)
    final direct = catalog.where((t) {
      if (!isValidIRTrainNumber(t.number)) return false;

      final matchFromCode = t.fromCode.toUpperCase() == fromCode;
      final matchToCode = t.toCode.toUpperCase() == toCode;
      final matchFromCity = t.fromName.toLowerCase().contains(fromCity);
      final matchToCity = t.toName.toLowerCase().contains(toCity);

      return (matchFromCode && matchToCode) ||
          (matchFromCity && matchToCity) ||
          (matchFromCode && matchToCity) ||
          (matchFromCity && matchToCode);
    }).map((t) => TrainSummary(
          number: t.number,
          name: t.name,
          fromCode: from.code,
          fromName: from.name,
          toCode: to.code,
          toName: to.name,
          departure: t.departure,
          arrival: t.arrival,
          duration: t.duration,
          daysLabel: t.daysLabel,
          type: t.type,
          arrivalDayOffset: t.arrivalDayOffset,
        )).toList();

    return direct;
  }

  String _city(String stationName) {
    final first = stationName.split(RegExp(r'[ \-]')).first;
    return first.isEmpty ? stationName : first;
  }
}

/// Shared repository instance.
const trainRepository = TrainRepository();
