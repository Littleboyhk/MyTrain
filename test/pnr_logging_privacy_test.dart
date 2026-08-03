// What a PNR lookup is allowed to write to the device log.
//
// THE LEAK. RapidApiService printed the entire response body at PNR request
// time. A PNR response lists, per passenger, the booking and current status
// strings — coach, berth and queue position each — so a single lookup wrote every
// passenger's seat allocation into the log. The request line also carried the PNR
// itself in the query string, and a PNR is enough on its own to look the booking
// up again.
//
// This captures debugPrint during a real lookup (mocked transport) and asserts
// the sensitive values are absent. Shape information is fine and is what makes a
// provider renaming a field noticeable.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_train/data/rapidapi_service.dart';

const String kPnr = '2451087345';

/// Realistic response: the strings here are exactly what used to be logged.
final Map<String, dynamic> kBody = {
  'data': {
    'train_number': '12951',
    'train_name': 'MUMBAI RAJDHANI',
    'boarding_point': 'BCT',
    'reservation_upto': 'NDLS',
    'class': 'SL',
    'passengers': [
      {'booking_status': 'CNF/B2/34/LB', 'current_status': 'CNF/B2/34/LB'},
      {'booking_status': 'RAC 21', 'current_status': 'CNF/S7/47/SLB'},
    ],
  },
};

/// Runs [body] with debugPrint captured.
Future<List<String>> captureLogs(Future<void> Function() body) async {
  final logs = <String>[];
  final original = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) logs.add(message);
  };
  try {
    await body();
  } finally {
    debugPrint = original;
  }
  return logs;
}

RapidApiService service() => RapidApiService(
      client: MockClient((_) async => http.Response(
            jsonEncode(kBody),
            200,
            headers: {'content-type': 'application/json'},
          )),
    );

void main() {
  test('a PNR lookup logs no passenger allocations and no PNR', () async {
    final logs = await captureLogs(() async {
      await service().getPnrStatus(kPnr);
    });

    expect(logs, isNotEmpty, reason: 'something should still be logged');
    final joined = logs.join('\n');

    // The PNR itself.
    expect(joined, isNot(contains(kPnr)));

    // Per-passenger allocations.
    for (final secret in [
      'CNF/B2/34/LB',
      'CNF/S7/47/SLB',
      'RAC 21',
      'booking_status',
      'current_status',
    ]) {
      expect(joined, isNot(contains(secret)), reason: 'leaked "$secret"');
    }
  });

  test('the raw body is not logged wholesale', () async {
    final logs = await captureLogs(() async {
      await service().getPnrStatus(kPnr);
    });
    final joined = logs.join('\n');

    // A body dump would necessarily contain the JSON braces-and-quotes shape of
    // the passenger list.
    expect(joined, isNot(contains('"passengers"')));
    expect(joined.contains(jsonEncode(kBody)), isFalse);
  });

  test('useful non-sensitive diagnostics survive', () async {
    final logs = await captureLogs(() async {
      await service().getPnrStatus(kPnr);
    });
    final joined = logs.join('\n');

    // Status, size and top-level key names are what make a renamed provider
    // field noticeable — several of this file's silent fallbacks went unseen for
    // exactly that reason.
    expect(joined, contains('HTTP 200'));
    expect(joined, contains('passengerRows=2'));
    expect(joined, contains('train_name'));
  });

  test('an error path redacts the PNR too', () async {
    // A decode failure can quote its input.
    final svc = RapidApiService(
      client: MockClient((_) async => http.Response('not json at all', 200)),
    );

    final logs = await captureLogs(() async {
      try {
        await svc.getPnrStatus(kPnr);
      } catch (_) {
        // Expected — we only care what was written on the way out.
      }
    });

    expect(logs.join('\n'), isNot(contains(kPnr)));
  });

  test('the thrown exception message does not carry the PNR', () async {
    final svc = RapidApiService(
      client: MockClient((_) async => http.Response('not json at all', 200)),
    );

    Object? caught;
    try {
      await svc.getPnrStatus(kPnr);
    } catch (e) {
      caught = e;
    }
    expect(caught, isNotNull);
    // The message can surface in UI error states, so it is held to the same bar.
    expect(caught.toString(), isNot(contains(kPnr)));
  });
}
