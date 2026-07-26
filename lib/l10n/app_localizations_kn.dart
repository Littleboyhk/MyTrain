// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Kannada (`kn`).
class L10nKn extends L10n {
  L10nKn([String locale = 'kn']) : super(locale);

  @override
  String get appName => 'My Train';

  @override
  String get navTrack => 'ಟ್ರ್ಯಾಕ್';

  @override
  String get navPnr => 'PNR';

  @override
  String get navBook => 'ಬುಕಿಂಗ್';

  @override
  String get navProfile => 'ಪ್ರೊಫೈಲ್';

  @override
  String get heroTitle => 'ನಿಮ್ಮ ಮುಂದಿನ ಪ್ರಯಾಣವನ್ನು ಟ್ರ್ಯಾಕ್ ಮಾಡಿ';

  @override
  String get heroSubtitle =>
      'ಭಾರತದಾದ್ಯಂತ ಲೈವ್ ಸ್ಥಿತಿ, PNR ಮತ್ತು ಪ್ಲಾಟ್‌ಫಾರ್ಮ್ ಮಾಹಿತಿ';

  @override
  String get nearestStation => 'ಹತ್ತಿರದ ನಿಲ್ದಾಣ';

  @override
  String get usingNearestStation => 'ಹತ್ತಿರದ ನಿಲ್ದಾಣವನ್ನು ಬಳಸಲಾಗುತ್ತಿದೆ';

  @override
  String get searchByRoute => 'ಮಾರ್ಗದ ಮೂಲಕ';

  @override
  String get searchByTrainNo => 'ರೈಲು ಸಂಖ್ಯೆಯ ಮೂಲಕ';

  @override
  String get fieldFrom => 'ಎಲ್ಲಿಂದ';

  @override
  String get fieldTo => 'ಎಲ್ಲಿಗೆ';

  @override
  String get selectStation => 'ನಿಲ್ದಾಣ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get searchTrains => 'ರೈಲುಗಳನ್ನು ಹುಡುಕಿ';

  @override
  String get hintTrainNumber => 'ರೈಲು ಸಂಖ್ಯೆ ನಮೂದಿಸಿ (ಉದಾ. 12951)';

  @override
  String get hintSearchAny => 'ರೈಲಿನ ಹೆಸರು, ಸಂಖ್ಯೆ ಅಥವಾ ನಿಲ್ದಾಣ ಹುಡುಕಿ';

  @override
  String get searchCityStationCode => 'ನಗರ, ನಿಲ್ದಾಣ ಅಥವಾ ಕೋಡ್ ಹುಡುಕಿ';

  @override
  String get selectOrigin => 'ಹೊರಡುವ ನಿಲ್ದಾಣ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get selectDestination => 'ತಲುಪುವ ನಿಲ್ದಾಣ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get sectionRecent => 'ಇತ್ತೀಚಿನ';

  @override
  String get sectionPopular => 'ಜನಪ್ರಿಯ ನಿಲ್ದಾಣಗಳು';

  @override
  String get filterAllTrains => 'ಎಲ್ಲಾ ರೈಲುಗಳು';

  @override
  String get filterNearby => 'ಹತ್ತಿರದಲ್ಲಿ';

  @override
  String get filterRunningStatus => 'ಚಾಲನಾ ಸ್ಥಿತಿ';

  @override
  String get filterPnrStatus => 'PNR ಸ್ಥಿತಿ';

  @override
  String get filterLiveMap => 'ಲೈವ್ ನಕ್ಷೆ';

  @override
  String get filterExpress => 'ಎಕ್ಸ್‌ಪ್ರೆಸ್';

  @override
  String get filterSuperfast => 'ಸೂಪರ್‌ಫಾಸ್ಟ್';

  @override
  String get filterPassenger => 'ಪ್ಯಾಸೆಂಜರ್';

  @override
  String get filterOnTime => 'ಸಮಯಕ್ಕೆ';

  @override
  String get filterDelayed => 'ವಿಳಂಬ';

  @override
  String countDepartures(int count) {
    return '$count ಮುಂದಿನ ನಿರ್ಗಮನಗಳು';
  }

  @override
  String countNearYou(int count) {
    return 'ನಿಮ್ಮ ಹತ್ತಿರ $count ರೈಲುಗಳು';
  }

  @override
  String countRunning(int count) {
    return '$count ರೈಲುಗಳು ಚಲಿಸುತ್ತಿವೆ';
  }

  @override
  String countOnRoute(int count, Object from, Object to) {
    return '$count ರೈಲುಗಳು · $from → $to';
  }

  @override
  String countMatching(int count, Object query) {
    return '\"$query\" ಗೆ ಹೊಂದುವ $count';
  }

  @override
  String get noTrainsMatch => 'ನಿಮ್ಮ ಫಿಲ್ಟರ್‌ಗಳಿಗೆ ಯಾವುದೇ ರೈಲು ಹೊಂದುತ್ತಿಲ್ಲ';

  @override
  String get statusOnTime => 'ಸಮಯಕ್ಕೆ';

  @override
  String statusDelayedMin(int minutes) {
    return '$minutes ನಿಮಿಷ ವಿಳಂಬ';
  }

  @override
  String platformAndEta(Object platform, int minutes) {
    return 'PF $platform · $minutes ನಿಮಿಷದಲ್ಲಿ';
  }

  @override
  String get platformTba => 'ಪ್ಲಾಟ್‌ಫಾರ್ಮ್ ಘೋಷಿಸಿಲ್ಲ';

  @override
  String get liveGps => 'ಲೈವ್ GPS';

  @override
  String get pantry => 'ಪ್ಯಾಂಟ್ರಿ';

  @override
  String get acThreeTier => 'AC 3-ಟಯರ್';

  @override
  String get acTwoTier => 'AC 2-ಟಯರ್';

  @override
  String scheduledDays(Object days) {
    return 'ನಿಗದಿತ · $days';
  }

  @override
  String get runsDaily => 'ಪ್ರತಿದಿನ';

  @override
  String get bookTitle => 'ನಿಮ್ಮ ಟಿಕೆಟ್ ಬುಕ್ ಮಾಡಿ';

  @override
  String get bookBody =>
      'ಕಾಯ್ದಿರಿಸುವಿಕೆ ಅಧಿಕೃತ IRCTC ಪೋರ್ಟಲ್‌ನಲ್ಲಿ ನಡೆಯುತ್ತದೆ.';

  @override
  String get bookCta => 'IRCTC ಗೆ ಮುಂದುವರಿಯಿರಿ';

  @override
  String get bookSheetTitle => 'IRCTC ನಲ್ಲಿ ಬುಕ್ ಮಾಡಿ';

  @override
  String get bookSheetBody =>
      'ಟಿಕೆಟ್ ಬುಕಿಂಗ್ ಅಧಿಕೃತ IRCTC ಪೋರ್ಟಲ್‌ನಲ್ಲಿ ನಡೆಯುತ್ತದೆ.';

  @override
  String get bookOpening => 'IRCTC ತೆರೆಯುತ್ತಿದೆ — ಸಂಯೋಜನೆ ಶೀಘ್ರದಲ್ಲೇ';

  @override
  String get cancel => 'ರದ್ದುಮಾಡಿ';

  @override
  String get tryAgain => 'ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ';

  @override
  String get gotIt => 'ಅರ್ಥವಾಯಿತು';

  @override
  String get pnrHint => '10 ಅಂಕಿಯ PNR';

  @override
  String get pnrCheckCta => 'PNR ಸ್ಥಿತಿ ಪರಿಶೀಲಿಸಿ';

  @override
  String get pnrNotFoundTitle => 'PNR ಕಂಡುಬಂದಿಲ್ಲ';

  @override
  String pnrNotFoundBody(Object pnr) {
    return 'PNR $pnr ಸಿಗಲಿಲ್ಲ. ನಿಮ್ಮ ಟಿಕೆಟ್‌ನಲ್ಲಿರುವ 10 ಅಂಕಿಯ ಸಂಖ್ಯೆ ಪರಿಶೀಲಿಸಿ ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.';
  }

  @override
  String get pnrSampleTip =>
      'ಸಲಹೆ: ಲೈವ್ ಉದಾಹರಣೆ ನೋಡಲು ಮೇಲಿನ ಮಾದರಿಯನ್ನು ಟ್ಯಾಪ್ ಮಾಡಿ.';

  @override
  String get pnrSampleConfirmed => 'ಖಚಿತ';

  @override
  String get pnrSampleWaitlisted => 'ಕಾಯುವ ಪಟ್ಟಿ';

  @override
  String get pnrSampleMixed => 'ಮಿಶ್ರ';

  @override
  String get checkBackLaterTitle => 'ನಂತರ ಪರಿಶೀಲಿಸಿ';

  @override
  String get pnrQuotaBody =>
      'ಮಾಸಿಕ ವಿನಂತಿ ಮಿತಿ ತಲುಪಿದ್ದರಿಂದ ಲೈವ್ PNR ಮಾಹಿತಿ ತಾತ್ಕಾಲಿಕವಾಗಿ ಲಭ್ಯವಿಲ್ಲ. ನಂತರ ಪ್ರಯತ್ನಿಸಿ.';

  @override
  String get routeUnavailableTitle => 'ಮಾರ್ಗ ಲಭ್ಯವಿಲ್ಲ';

  @override
  String routeUnavailableGeneric(Object number) {
    return 'ರೈಲು $number ರ ಮಾರ್ಗ ಲೋಡ್ ಆಗಲಿಲ್ಲ.';
  }

  @override
  String get routeUnavailableNotConnected =>
      'ಈ ಬಿಲ್ಡ್‌ನಲ್ಲಿ ಲೈವ್ ಮಾರ್ಗ ಡೇಟಾ ಇನ್ನೂ ಸಂಪರ್ಕಗೊಂಡಿಲ್ಲ.';

  @override
  String get routeUnavailableQuota =>
      'ಲೈವ್ ರೈಲ್ವೆ ಡೇಟಾ ತಾತ್ಕಾಲಿಕವಾಗಿ ಲಭ್ಯವಿಲ್ಲ. ನಂತರ ಪರಿಶೀಲಿಸಿ.';

  @override
  String routeUnavailableInconsistent(Object number) {
    return 'ರೈಲು $number ರ ಮಾರ್ಗ ಡೇಟಾ ಅಸಂಗತವಾಗಿ ಕಾಣುತ್ತದೆ, ಆದ್ದರಿಂದ ತೋರಿಸಲಾಗಿಲ್ಲ.';
  }

  @override
  String liveTimelineStations(int count) {
    return 'ಲೈವ್ ಟೈಮ್‌ಲೈನ್ · $count ನಿಲ್ದಾಣಗಳು';
  }

  @override
  String get destinationAlarm => 'ಗಮ್ಯಸ್ಥಾನ ಅಲಾರಂ';

  @override
  String get coachPosition => 'ಕೋಚ್ ಸ್ಥಾನ';

  @override
  String get setAlarm => 'ಅಲಾರಂ ಹೊಂದಿಸಿ';

  @override
  String get unableToFetchRoute => 'ಮಾರ್ಗ ಪಡೆಯಲಾಗಲಿಲ್ಲ. ಸಂಪರ್ಕ ಪರಿಶೀಲಿಸಿ.';

  @override
  String get settingsTitle => 'ಸೆಟ್ಟಿಂಗ್‌ಗಳು';

  @override
  String get sectionAppearance => 'ಗೋಚರತೆ';

  @override
  String get themeSystem => 'ಸಿಸ್ಟಂ';

  @override
  String get themeLight => 'ಲೈಟ್';

  @override
  String get themeDark => 'ಡಾರ್ಕ್';

  @override
  String get appearanceHint =>
      'My Train ಹೇಗೆ ಕಾಣಬೇಕೆಂದು ಆಯ್ಕೆಮಾಡಿ. \"ಸಿಸ್ಟಂ\" ನಿಮ್ಮ ಸಾಧನದ ಸೆಟ್ಟಿಂಗ್ ಅನುಸರಿಸುತ್ತದೆ.';

  @override
  String get sectionLanguage => 'ಭಾಷೆ';

  @override
  String get language => 'ಭಾಷೆ';

  @override
  String get sectionAbout => 'ಅಪ್ಲಿಕೇಶನ್ ಬಗ್ಗೆ';

  @override
  String aboutVersion(Object version) {
    return 'ಆವೃತ್ತಿ $version';
  }

  @override
  String get aboutCoverage => 'ವ್ಯಾಪ್ತಿ';

  @override
  String aboutCoverageValue(Object count) {
    return '$count ರೈಲ್ವೆ ನಿಲ್ದಾಣಗಳು';
  }

  @override
  String get aboutStationData => 'ನಿಲ್ದಾಣ ಡೇಟಾ';

  @override
  String get chooseLanguage => 'ಭಾಷೆ ಆಯ್ಕೆಮಾಡಿ';

  @override
  String get chooseLanguageSubtitle =>
      'My Train ಅನ್ನು ಯಾವ ಭಾಷೆಯಲ್ಲಿ ಓದಬೇಕೆಂದು ಆಯ್ಕೆಮಾಡಿ.';

  @override
  String get submit => 'ಸಲ್ಲಿಸು';

  @override
  String languageChanged(Object language) {
    return 'ಭಾಷೆ $language ಗೆ ಹೊಂದಿಸಲಾಗಿದೆ';
  }

  @override
  String platformNumber(Object platform) {
    return 'ಪ್ಲಾಟ್‌ಫಾರ್ಮ್ $platform';
  }

  @override
  String get weekdayLetters => 'ಭಾ,ಸೋ,ಮ,ಬು,ಗು,ಶು,ಶ';

  @override
  String runsUntil(Object date) {
    return '$date ವರೆಗೆ ಚಲಿಸುತ್ತದೆ';
  }
}
