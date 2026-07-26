// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Panjabi Punjabi (`pa`).
class L10nPa extends L10n {
  L10nPa([String locale = 'pa']) : super(locale);

  @override
  String get appName => 'My Train';

  @override
  String get navTrack => 'ਟਰੈਕ';

  @override
  String get navPnr => 'PNR';

  @override
  String get navBook => 'ਬੁਕਿੰਗ';

  @override
  String get navProfile => 'ਪ੍ਰੋਫਾਈਲ';

  @override
  String get heroTitle => 'ਆਪਣੇ ਅਗਲੇ ਸਫ਼ਰ ਨੂੰ ਟਰੈਕ ਕਰੋ';

  @override
  String get heroSubtitle =>
      'ਪੂਰੇ ਭਾਰਤ ਵਿੱਚ ਲਾਈਵ ਸਥਿਤੀ, PNR ਅਤੇ ਪਲੇਟਫਾਰਮ ਜਾਣਕਾਰੀ';

  @override
  String get nearestStation => 'ਨੇੜਲਾ ਸਟੇਸ਼ਨ';

  @override
  String get usingNearestStation => 'ਨੇੜਲਾ ਸਟੇਸ਼ਨ ਵਰਤਿਆ ਜਾ ਰਿਹਾ ਹੈ';

  @override
  String get searchByRoute => 'ਰੂਟ ਅਨੁਸਾਰ';

  @override
  String get searchByTrainNo => 'ਗੱਡੀ ਨੰਬਰ ਅਨੁਸਾਰ';

  @override
  String get fieldFrom => 'ਕਿੱਥੋਂ';

  @override
  String get fieldTo => 'ਕਿੱਥੇ';

  @override
  String get selectStation => 'ਸਟੇਸ਼ਨ ਚੁਣੋ';

  @override
  String get searchTrains => 'ਗੱਡੀਆਂ ਲੱਭੋ';

  @override
  String get hintTrainNumber => 'ਗੱਡੀ ਨੰਬਰ ਦਰਜ ਕਰੋ (ਜਿਵੇਂ 12951)';

  @override
  String get hintSearchAny => 'ਗੱਡੀ ਦਾ ਨਾਮ, ਨੰਬਰ ਜਾਂ ਸਟੇਸ਼ਨ ਲੱਭੋ';

  @override
  String get searchCityStationCode => 'ਸ਼ਹਿਰ, ਸਟੇਸ਼ਨ ਜਾਂ ਕੋਡ ਲੱਭੋ';

  @override
  String get selectOrigin => 'ਰਵਾਨਗੀ ਸਟੇਸ਼ਨ ਚੁਣੋ';

  @override
  String get selectDestination => 'ਮੰਜ਼ਿਲ ਸਟੇਸ਼ਨ ਚੁਣੋ';

  @override
  String get sectionRecent => 'ਹਾਲੀਆ';

  @override
  String get sectionPopular => 'ਪ੍ਰਸਿੱਧ ਸਟੇਸ਼ਨ';

  @override
  String get filterAllTrains => 'ਸਾਰੀਆਂ ਗੱਡੀਆਂ';

  @override
  String get filterNearby => 'ਨੇੜੇ';

  @override
  String get filterRunningStatus => 'ਚੱਲਣ ਦੀ ਸਥਿਤੀ';

  @override
  String get filterPnrStatus => 'PNR ਸਥਿਤੀ';

  @override
  String get filterLiveMap => 'ਲਾਈਵ ਨਕਸ਼ਾ';

  @override
  String get filterExpress => 'ਐਕਸਪ੍ਰੈਸ';

  @override
  String get filterSuperfast => 'ਸੁਪਰਫਾਸਟ';

  @override
  String get filterPassenger => 'ਪੈਸੰਜਰ';

  @override
  String get filterOnTime => 'ਸਮੇਂ ਸਿਰ';

  @override
  String get filterDelayed => 'ਦੇਰੀ';

  @override
  String countDepartures(int count) {
    return '$count ਆਉਣ ਵਾਲੀਆਂ ਰਵਾਨਗੀਆਂ';
  }

  @override
  String countNearYou(int count) {
    return 'ਤੁਹਾਡੇ ਨੇੜੇ $count ਗੱਡੀਆਂ';
  }

  @override
  String countRunning(int count) {
    return '$count ਗੱਡੀਆਂ ਚੱਲ ਰਹੀਆਂ ਹਨ';
  }

  @override
  String countOnRoute(int count, Object from, Object to) {
    return '$count ਗੱਡੀਆਂ · $from → $to';
  }

  @override
  String countMatching(int count, Object query) {
    return '\"$query\" ਨਾਲ ਮੇਲ ਖਾਂਦੀਆਂ $count';
  }

  @override
  String get noTrainsMatch => 'ਤੁਹਾਡੇ ਫਿਲਟਰਾਂ ਨਾਲ ਕੋਈ ਗੱਡੀ ਮੇਲ ਨਹੀਂ ਖਾਂਦੀ';

  @override
  String get statusOnTime => 'ਸਮੇਂ ਸਿਰ';

  @override
  String statusDelayedMin(int minutes) {
    return '$minutes ਮਿੰਟ ਦੇਰੀ';
  }

  @override
  String platformAndEta(Object platform, int minutes) {
    return 'PF $platform · $minutes ਮਿੰਟ ਵਿੱਚ';
  }

  @override
  String get platformTba => 'ਪਲੇਟਫਾਰਮ ਐਲਾਨ ਨਹੀਂ ਹੋਇਆ';

  @override
  String get liveGps => 'ਲਾਈਵ GPS';

  @override
  String get pantry => 'ਪੈਂਟਰੀ';

  @override
  String get acThreeTier => 'AC 3-ਟੀਅਰ';

  @override
  String get acTwoTier => 'AC 2-ਟੀਅਰ';

  @override
  String scheduledDays(Object days) {
    return 'ਨਿਰਧਾਰਿਤ · $days';
  }

  @override
  String get runsDaily => 'ਰੋਜ਼ਾਨਾ';

  @override
  String get bookTitle => 'ਆਪਣੀ ਟਿਕਟ ਬੁੱਕ ਕਰੋ';

  @override
  String get bookBody => 'ਰਿਜ਼ਰਵੇਸ਼ਨ ਸਰਕਾਰੀ IRCTC ਪੋਰਟਲ \'ਤੇ ਹੁੰਦੀ ਹੈ।';

  @override
  String get bookCta => 'IRCTC \'ਤੇ ਜਾਰੀ ਰੱਖੋ';

  @override
  String get bookSheetTitle => 'IRCTC \'ਤੇ ਬੁੱਕ ਕਰੋ';

  @override
  String get bookSheetBody => 'ਟਿਕਟ ਬੁਕਿੰਗ ਸਰਕਾਰੀ IRCTC ਪੋਰਟਲ \'ਤੇ ਹੁੰਦੀ ਹੈ।';

  @override
  String get bookOpening => 'IRCTC ਖੁੱਲ੍ਹ ਰਿਹਾ ਹੈ — ਏਕੀਕਰਨ ਜਲਦੀ';

  @override
  String get cancel => 'ਰੱਦ ਕਰੋ';

  @override
  String get tryAgain => 'ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ';

  @override
  String get gotIt => 'ਸਮਝ ਗਿਆ';

  @override
  String get pnrHint => '10 ਅੰਕਾਂ ਦਾ PNR';

  @override
  String get pnrCheckCta => 'PNR ਸਥਿਤੀ ਵੇਖੋ';

  @override
  String get pnrNotFoundTitle => 'PNR ਨਹੀਂ ਮਿਲਿਆ';

  @override
  String pnrNotFoundBody(Object pnr) {
    return 'PNR $pnr ਨਹੀਂ ਮਿਲਿਆ। ਆਪਣੀ ਟਿਕਟ \'ਤੇ 10 ਅੰਕਾਂ ਦਾ ਨੰਬਰ ਜਾਂਚੋ ਅਤੇ ਦੁਬਾਰਾ ਕੋਸ਼ਿਸ਼ ਕਰੋ।';
  }

  @override
  String get pnrSampleTip =>
      'ਸੁਝਾਅ: ਲਾਈਵ ਉਦਾਹਰਨ ਵੇਖਣ ਲਈ ਉੱਪਰ ਦਿੱਤੇ ਨਮੂਨੇ \'ਤੇ ਟੈਪ ਕਰੋ।';

  @override
  String get pnrSampleConfirmed => 'ਪੱਕਾ';

  @override
  String get pnrSampleWaitlisted => 'ਵੇਟਿੰਗ ਲਿਸਟ';

  @override
  String get pnrSampleMixed => 'ਮਿਸ਼ਰਤ';

  @override
  String get checkBackLaterTitle => 'ਬਾਅਦ ਵਿੱਚ ਵੇਖੋ';

  @override
  String get pnrQuotaBody =>
      'ਮਹੀਨਾਵਾਰ ਬੇਨਤੀ ਸੀਮਾ ਪੂਰੀ ਹੋਣ ਕਾਰਨ ਲਾਈਵ PNR ਜਾਣਕਾਰੀ ਹਾਲੇ ਉਪਲਬਧ ਨਹੀਂ। ਕਿਰਪਾ ਕਰਕੇ ਬਾਅਦ ਵਿੱਚ ਕੋਸ਼ਿਸ਼ ਕਰੋ।';

  @override
  String get routeUnavailableTitle => 'ਰੂਟ ਉਪਲਬਧ ਨਹੀਂ';

  @override
  String routeUnavailableGeneric(Object number) {
    return 'ਗੱਡੀ $number ਦਾ ਰੂਟ ਲੋਡ ਨਹੀਂ ਹੋ ਸਕਿਆ।';
  }

  @override
  String get routeUnavailableNotConnected =>
      'ਇਸ ਬਿਲਡ ਵਿੱਚ ਲਾਈਵ ਰੂਟ ਡਾਟਾ ਹਾਲੇ ਜੁੜਿਆ ਨਹੀਂ ਹੈ।';

  @override
  String get routeUnavailableQuota =>
      'ਲਾਈਵ ਰੇਲਵੇ ਡਾਟਾ ਹਾਲੇ ਉਪਲਬਧ ਨਹੀਂ। ਕਿਰਪਾ ਕਰਕੇ ਬਾਅਦ ਵਿੱਚ ਵੇਖੋ।';

  @override
  String routeUnavailableInconsistent(Object number) {
    return 'ਗੱਡੀ $number ਦਾ ਰੂਟ ਡਾਟਾ ਅਸੰਗਤ ਲੱਗਦਾ ਹੈ, ਇਸ ਲਈ ਨਹੀਂ ਦਿਖਾਇਆ ਜਾ ਰਿਹਾ।';
  }

  @override
  String liveTimelineStations(int count) {
    return 'ਲਾਈਵ ਟਾਈਮਲਾਈਨ · $count ਸਟੇਸ਼ਨ';
  }

  @override
  String get destinationAlarm => 'ਮੰਜ਼ਿਲ ਅਲਾਰਮ';

  @override
  String get coachPosition => 'ਕੋਚ ਸਥਿਤੀ';

  @override
  String get setAlarm => 'ਅਲਾਰਮ ਲਗਾਓ';

  @override
  String get unableToFetchRoute => 'ਰੂਟ ਪ੍ਰਾਪਤ ਨਹੀਂ ਹੋ ਸਕਿਆ। ਕਨੈਕਸ਼ਨ ਜਾਂਚੋ।';

  @override
  String get settingsTitle => 'ਸੈਟਿੰਗਾਂ';

  @override
  String get sectionAppearance => 'ਦਿੱਖ';

  @override
  String get themeSystem => 'ਸਿਸਟਮ';

  @override
  String get themeLight => 'ਲਾਈਟ';

  @override
  String get themeDark => 'ਡਾਰਕ';

  @override
  String get appearanceHint =>
      'My Train ਕਿਹੋ ਜਿਹਾ ਦਿਖੇ ਚੁਣੋ। \"ਸਿਸਟਮ\" ਤੁਹਾਡੇ ਡਿਵਾਈਸ ਦੀ ਸੈਟਿੰਗ ਮੰਨਦਾ ਹੈ।';

  @override
  String get sectionLanguage => 'ਭਾਸ਼ਾ';

  @override
  String get language => 'ਭਾਸ਼ਾ';

  @override
  String get sectionAbout => 'ਐਪ ਬਾਰੇ';

  @override
  String aboutVersion(Object version) {
    return 'ਵਰਜਨ $version';
  }

  @override
  String get aboutCoverage => 'ਕਵਰੇਜ';

  @override
  String aboutCoverageValue(Object count) {
    return '$count ਰੇਲਵੇ ਸਟੇਸ਼ਨ';
  }

  @override
  String get aboutStationData => 'ਸਟੇਸ਼ਨ ਡਾਟਾ';

  @override
  String get chooseLanguage => 'ਭਾਸ਼ਾ ਚੁਣੋ';

  @override
  String get chooseLanguageSubtitle =>
      'My Train ਕਿਸ ਭਾਸ਼ਾ ਵਿੱਚ ਪੜ੍ਹਨਾ ਚਾਹੁੰਦੇ ਹੋ ਚੁਣੋ।';

  @override
  String get submit => 'ਜਮ੍ਹਾਂ ਕਰੋ';

  @override
  String languageChanged(Object language) {
    return 'ਭਾਸ਼ਾ $language \'ਤੇ ਸੈੱਟ ਕੀਤੀ';
  }

  @override
  String platformNumber(Object platform) {
    return 'ਪਲੇਟਫਾਰਮ $platform';
  }

  @override
  String get weekdayLetters => 'ਐ,ਸੋ,ਮੰ,ਬੁੱ,ਵੀ,ਸ਼ੁੱ,ਸ਼';

  @override
  String runsUntil(Object date) {
    return '$date ਤੱਕ ਚੱਲਦੀ ਹੈ';
  }
}
