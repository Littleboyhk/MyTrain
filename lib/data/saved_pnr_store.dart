import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pnr_status.dart';
import '../models/train_summary.dart';

/// Upgrade notification payload when a passenger status improves.
class PnrUpgradeEvent {
  final String pnr;
  final String trainNumber;
  final String trainName;
  final int passengerIndex;
  final String oldStatus;
  final String newStatus;

  const PnrUpgradeEvent({
    required this.pnr,
    required this.trainNumber,
    required this.trainName,
    required this.passengerIndex,
    required this.oldStatus,
    required this.newStatus,
  });
}

/// Store managing saved PNR ticket history and status upgrade detection.
class SavedPnrStore {
  SavedPnrStore._();
  static final SavedPnrStore instance = SavedPnrStore._();

  static const String _key = 'saved_pnrs_v1';

  /// Save or update a PNR result in local storage.
  ///
  /// Returns a [PnrUpgradeEvent] if a passenger status upgraded (e.g. WL -> CNF).
  Future<PnrUpgradeEvent?> savePnr(PnrResult result) async {
    try {
      final existing = await getSavedPnrs();
      PnrUpgradeEvent? upgradeEvent;

      // Check if previously saved version had a waitlisted passenger that is now confirmed/RAC
      final prevIndex = existing.indexWhere((p) => p.pnr == result.pnr);
      if (prevIndex != -1) {
        final oldResult = existing[prevIndex];
        for (int i = 0; i < result.passengers.length; i++) {
          final newP = result.passengers[i];
          if (i < oldResult.passengers.length) {
            final oldP = oldResult.passengers[i];
            if (oldP.current.status == PassengerStatus.waitlisted &&
                (newP.current.status == PassengerStatus.confirmed ||
                    newP.current.status == PassengerStatus.rac)) {
              upgradeEvent = PnrUpgradeEvent(
                pnr: result.pnr,
                trainNumber: result.train.number,
                trainName: result.train.name,
                passengerIndex: newP.index,
                oldStatus: oldP.current.display,
                newStatus: newP.current.display,
              );
              break;
            }
          }
        }
      }

      // Upsert into list
      final updatedList = existing.where((p) => p.pnr != result.pnr).toList()
        ..insert(0, result);

      final prefs = await SharedPreferences.getInstance();
      final jsonList = updatedList.map(_toJson).toList();
      await prefs.setString(_key, jsonEncode(jsonList));

      return upgradeEvent;
    } catch (e) {
      debugPrint('[SavedPnrStore] Error saving PNR: $e');
      return null;
    }
  }

  /// Get all saved PNR tickets from storage.
  Future<List<PnrResult>> getSavedPnrs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null || raw.trim().isEmpty) {
        final initial = [_defaultGaribRath()];
        await savePnr(initial.first);
        return initial;
      }

      final List decoded = jsonDecode(raw);
      final out = <PnrResult>[];
      for (final item in decoded) {
        if (item is Map) {
          final parsed = _fromJson(item.cast<String, dynamic>());
          if (parsed != null) out.add(parsed);
        }
      }
      if (out.isEmpty) {
        final initial = [_defaultGaribRath()];
        await savePnr(initial.first);
        return initial;
      }
      return out;
    } catch (e) {
      debugPrint('[SavedPnrStore] Error reading saved PNRs: $e');
      return [_defaultGaribRath()];
    }
  }

  PnrResult _defaultGaribRath() {
    return PnrResult(
      pnr: '4240508234',
      train: const TrainSummary(
        number: '12257',
        name: 'YPR TVCN GR EXP',
        fromCode: 'YPR',
        fromName: 'YESVANTPUR JN.',
        toCode: 'KYJ',
        toName: 'KAYANKULAM JN',
        departure: '20:45',
        arrival: '10:48',
        duration: '14h 03m',
        daysLabel: 'Sun, Tue, Thu',
        type: 'Garib Rath Express',
      ),
      journeyDate: DateTime.now().add(const Duration(days: 18)),
      travelClass: '3A',
      chartStatus: ChartStatus.notPrepared,
      passengers: const [
        PnrPassenger(
          index: 1,
          booking: SeatAllocation.confirmed('G15', '5', 'Middle berth'),
          current: SeatAllocation.confirmed('G15', '5', 'Middle berth'),
        ),
      ],
    );
  }

  /// Remove a PNR from saved tickets.
  Future<void> removePnr(String pnr) async {
    try {
      final existing = await getSavedPnrs();
      final updated = existing.where((p) => p.pnr != pnr).toList();
      final prefs = await SharedPreferences.getInstance();
      final jsonList = updated.map(_toJson).toList();
      await prefs.setString(_key, jsonEncode(jsonList));
    } catch (e) {
      debugPrint('[SavedPnrStore] Error removing PNR: $e');
    }
  }

  Map<String, dynamic> _toJson(PnrResult p) {
    return {
      'pnr': p.pnr,
      'train': {
        'number': p.train.number,
        'name': p.train.name,
        'fromCode': p.train.fromCode,
        'fromName': p.train.fromName,
        'toCode': p.train.toCode,
        'toName': p.train.toName,
        'departure': p.train.departure,
        'arrival': p.train.arrival,
        'duration': p.train.duration,
        'daysLabel': p.train.daysLabel,
        'type': p.train.type,
      },
      'journeyDate': p.journeyDate?.toIso8601String(),
      'travelClass': p.travelClass,
      'chartStatus': p.chartStatus?.name,
      'passengers': p.passengers
          .map((pass) => {
                'index': pass.index,
                'booking': pass.booking.berthLine,
                'current': pass.current.berthLine,
              })
          .toList(),
    };
  }

  PnrResult? _fromJson(Map<String, dynamic> map) {
    try {
      final pnr = map['pnr']?.toString() ?? '';
      final tMap = map['train'] as Map?;
      if (pnr.isEmpty || tMap == null) return null;

      final train = TrainSummary(
        number: tMap['number']?.toString() ?? '',
        name: tMap['name']?.toString() ?? '',
        fromCode: tMap['fromCode']?.toString() ?? '',
        fromName: tMap['fromName']?.toString() ?? '',
        toCode: tMap['toCode']?.toString() ?? '',
        toName: tMap['toName']?.toString() ?? '',
        departure: tMap['departure']?.toString() ?? '--:--',
        arrival: tMap['arrival']?.toString() ?? '--:--',
        duration: tMap['duration']?.toString() ?? '--',
        daysLabel: tMap['daysLabel']?.toString() ?? 'Daily',
        type: tMap['type']?.toString() ?? 'Express',
      );

      final jDateStr = map['journeyDate']?.toString();
      final jDate = jDateStr != null ? DateTime.tryParse(jDateStr) : null;
      final travelClass = map['travelClass']?.toString();
      final chartStr = map['chartStatus']?.toString();
      final chartStatus = chartStr == 'prepared'
          ? ChartStatus.prepared
          : chartStr == 'notPrepared'
              ? ChartStatus.notPrepared
              : null;

      final pList = map['passengers'] as List?;
      final passengers = <PnrPassenger>[];
      if (pList != null) {
        for (int i = 0; i < pList.length; i++) {
          final pm = pList[i] as Map?;
          if (pm != null) {
            final idx = (pm['index'] as num?)?.toInt() ?? (i + 1);
            final bStr = pm['booking']?.toString() ?? 'CNF';
            final cStr = pm['current']?.toString() ?? bStr;
            passengers.add(PnrPassenger(
              index: idx,
              booking: SeatAllocation.fromStatusString(bStr),
              current: SeatAllocation.fromStatusString(cStr),
            ));
          }
        }
      }

      return PnrResult(
        pnr: pnr,
        train: train,
        journeyDate: jDate,
        travelClass: travelClass,
        chartStatus: chartStatus,
        passengers: passengers.isNotEmpty
            ? passengers
            : [
                PnrPassenger(
                  index: 1,
                  booking: const SeatAllocation.confirmed(null, null),
                  current: const SeatAllocation.confirmed(null, null),
                )
              ],
      );
    } catch (e) {
      debugPrint('[SavedPnrStore] Error parsing JSON PNR: $e');
      return null;
    }
  }
}
