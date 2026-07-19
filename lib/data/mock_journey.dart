import '../models/journey.dart';
import '../models/station.dart';

/// Seed data for the tracking screen while the real API is not yet wired in.
///
/// A recognisable long-distance route so the timeline has enough stops to show
/// off staggered entrance, passed/current/upcoming states and expansion.
class MockJourney {
  const MockJourney._();

  static Journey build() {
    final now = DateTime.now();
    final base = DateTime(now.year, now.month, now.day, 17, 0);
    DateTime at(int addMinutes) => base.add(Duration(minutes: addMinutes));

    return Journey(
      trainNumber: '12951',
      trainName: 'Mumbai Rajdhani Express',
      stations: [
        Station(
          code: 'BCT',
          name: 'Mumbai Central',
          distanceFromOriginKm: 0,
          scheduledDeparture: at(0),
          platform: '3',
        ),
        Station(
          code: 'BVI',
          name: 'Borivali',
          distanceFromOriginKm: 26,
          scheduledArrival: at(22),
          scheduledDeparture: at(24),
          platform: '5',
          isHalt: true,
        ),
        Station(
          code: 'VAPI',
          name: 'Vapi',
          distanceFromOriginKm: 167,
          scheduledArrival: at(118),
          scheduledDeparture: at(120),
          platform: '2',
        ),
        Station(
          code: 'ST',
          name: 'Surat',
          distanceFromOriginKm: 263,
          scheduledArrival: at(172),
          scheduledDeparture: at(177),
          platform: '4',
        ),
        Station(
          code: 'BRC',
          name: 'Vadodara Jn',
          distanceFromOriginKm: 392,
          scheduledArrival: at(258),
          scheduledDeparture: at(263),
          platform: '6',
          note: 'Long halt — pantry restock and crew change.',
        ),
        Station(
          code: 'RTM',
          name: 'Ratlam Jn',
          distanceFromOriginKm: 553,
          scheduledArrival: at(402),
          scheduledDeparture: at(410),
          platform: '1',
          delayMinutes: 6,
        ),
        Station(
          code: 'KOTA',
          name: 'Kota Jn',
          distanceFromOriginKm: 819,
          scheduledArrival: at(560),
          scheduledDeparture: at(565),
          platform: '2',
          delayMinutes: 9,
          note: 'Running late — expected to recover time before Kota.',
        ),
        Station(
          code: 'SWM',
          name: 'Sawai Madhopur',
          distanceFromOriginKm: 926,
          scheduledArrival: at(640),
          scheduledDeparture: at(642),
          platform: '3',
          isHalt: true,
          delayMinutes: 8,
        ),
        Station(
          code: 'NDLS',
          name: 'New Delhi',
          distanceFromOriginKm: 1384,
          scheduledArrival: at(905),
          platform: '16',
          delayMinutes: 11,
        ),
      ],
    );
  }
}
