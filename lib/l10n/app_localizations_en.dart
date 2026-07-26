// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class L10nEn extends L10n {
  L10nEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'My Train';

  @override
  String get navTrack => 'Track';

  @override
  String get navPnr => 'PNR';

  @override
  String get navBook => 'Book';

  @override
  String get navProfile => 'Profile';

  @override
  String get heroTitle => 'Track your next journey';

  @override
  String get heroSubtitle => 'Live status, PNR & platform info across India';

  @override
  String get nearestStation => 'Nearest Station';

  @override
  String get usingNearestStation => 'Using nearest station';

  @override
  String get searchByRoute => 'By Route';

  @override
  String get searchByTrainNo => 'By Train No.';

  @override
  String get fieldFrom => 'FROM';

  @override
  String get fieldTo => 'TO';

  @override
  String get selectStation => 'Select station';

  @override
  String get searchTrains => 'Search Trains';

  @override
  String get hintTrainNumber => 'Enter train number (e.g. 12951)';

  @override
  String get hintSearchAny => 'Search train name, number or station';

  @override
  String get searchCityStationCode => 'Search city, station or code';

  @override
  String get selectOrigin => 'Select origin';

  @override
  String get selectDestination => 'Select destination';

  @override
  String get sectionRecent => 'RECENT';

  @override
  String get sectionPopular => 'POPULAR STATIONS';

  @override
  String get filterAllTrains => 'All Trains';

  @override
  String get filterNearby => 'Nearby';

  @override
  String get filterRunningStatus => 'Running Status';

  @override
  String get filterPnrStatus => 'PNR Status';

  @override
  String get filterLiveMap => 'Live Map';

  @override
  String get filterExpress => 'Express';

  @override
  String get filterSuperfast => 'Superfast';

  @override
  String get filterPassenger => 'Passenger';

  @override
  String get filterOnTime => 'On Time';

  @override
  String get filterDelayed => 'Delayed';

  @override
  String countDepartures(int count) {
    return '$count upcoming departures';
  }

  @override
  String countNearYou(int count) {
    return '$count trains near you';
  }

  @override
  String countRunning(int count) {
    return '$count trains running';
  }

  @override
  String countOnRoute(int count, Object from, Object to) {
    return '$count trains · $from → $to';
  }

  @override
  String countMatching(int count, Object query) {
    return '$count matching \"$query\"';
  }

  @override
  String get noTrainsMatch => 'No trains match your filters';

  @override
  String get statusOnTime => 'On time';

  @override
  String statusDelayedMin(int minutes) {
    return 'Delayed ${minutes}m';
  }

  @override
  String platformAndEta(Object platform, int minutes) {
    return 'PF $platform · in $minutes min';
  }

  @override
  String get platformTba => 'Platform TBA';

  @override
  String get liveGps => 'Live GPS';

  @override
  String get pantry => 'Pantry';

  @override
  String get acThreeTier => 'AC 3-Tier';

  @override
  String get acTwoTier => 'AC 2-Tier';

  @override
  String scheduledDays(Object days) {
    return 'Scheduled · $days';
  }

  @override
  String get runsDaily => 'Daily';

  @override
  String get bookTitle => 'Book your tickets';

  @override
  String get bookBody =>
      'Reservations are handled on the official IRCTC portal.';

  @override
  String get bookCta => 'Continue to IRCTC';

  @override
  String get bookSheetTitle => 'Book on IRCTC';

  @override
  String get bookSheetBody =>
      'Ticket booking happens on the official IRCTC portal.';

  @override
  String get bookOpening => 'Opening IRCTC — integration coming soon';

  @override
  String get cancel => 'Cancel';

  @override
  String get tryAgain => 'Try again';

  @override
  String get gotIt => 'Got it';

  @override
  String get pnrHint => '10-digit PNR';

  @override
  String get pnrCheckCta => 'Check PNR Status';

  @override
  String get pnrNotFoundTitle => 'PNR not found';

  @override
  String pnrNotFoundBody(Object pnr) {
    return 'We couldn\'t find PNR $pnr. Double-check the 10-digit number on your ticket and try again.';
  }

  @override
  String get pnrSampleTip => 'Tip: tap a sample above to see a live example.';

  @override
  String get pnrSampleConfirmed => 'Confirmed';

  @override
  String get pnrSampleWaitlisted => 'Waitlisted';

  @override
  String get pnrSampleMixed => 'Mixed';

  @override
  String get checkBackLaterTitle => 'Check back later';

  @override
  String get pnrQuotaBody =>
      'Live PNR lookups are temporarily unavailable because the monthly request limit was reached. Please try again later.';

  @override
  String get routeUnavailableTitle => 'Route unavailable';

  @override
  String routeUnavailableGeneric(Object number) {
    return 'Couldn\'t load the route for train $number.';
  }

  @override
  String get routeUnavailableNotConnected =>
      'Live route data isn\'t connected in this build yet.';

  @override
  String get routeUnavailableQuota =>
      'Live railway data is temporarily unavailable. Please check back later.';

  @override
  String routeUnavailableInconsistent(Object number) {
    return 'Route data for train $number looks inconsistent, so it\'s not being shown.';
  }

  @override
  String liveTimelineStations(int count) {
    return 'LIVE TIMELINE · $count STATIONS';
  }

  @override
  String get destinationAlarm => 'Destination Alarm';

  @override
  String get coachPosition => 'Coach Position';

  @override
  String get setAlarm => 'Set Alarm';

  @override
  String get unableToFetchRoute =>
      'Unable to fetch route. Please check connection.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get sectionAppearance => 'APPEARANCE';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get appearanceHint =>
      'Choose how My Train looks. \"System\" follows your device setting automatically.';

  @override
  String get sectionLanguage => 'LANGUAGE';

  @override
  String get language => 'Language';

  @override
  String get sectionAbout => 'ABOUT';

  @override
  String aboutVersion(Object version) {
    return 'Version $version';
  }

  @override
  String get aboutCoverage => 'Coverage';

  @override
  String aboutCoverageValue(Object count) {
    return '$count railway stations';
  }

  @override
  String get aboutStationData => 'Station data';

  @override
  String get chooseLanguage => 'Choose a language';

  @override
  String get chooseLanguageSubtitle => 'Pick how you\'d like to read My Train.';

  @override
  String get submit => 'Submit';

  @override
  String languageChanged(Object language) {
    return 'Language set to $language';
  }

  @override
  String platformNumber(Object platform) {
    return 'Platform $platform';
  }

  @override
  String get weekdayLetters => 'S,M,T,W,Th,F,Sa';

  @override
  String runsUntil(Object date) {
    return 'Runs till $date';
  }
}
