// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Assamese (`as`).
class L10nAs extends L10n {
  L10nAs([String locale = 'as']) : super(locale);

  @override
  String get appName => 'My Train';

  @override
  String get navTrack => 'ট্ৰেক';

  @override
  String get navPnr => 'PNR';

  @override
  String get navBook => 'বুকিং';

  @override
  String get navProfile => 'প্ৰফাইল';

  @override
  String get heroTitle => 'আপোনাৰ পৰৱৰ্তী যাত্ৰা ট্ৰেক কৰক';

  @override
  String get heroSubtitle => 'সমগ্ৰ ভাৰতত লাইভ স্থিতি, PNR আৰু প্লেটফৰ্ম তথ্য';

  @override
  String get nearestStation => 'নিকটতম স্টেচন';

  @override
  String get usingNearestStation => 'নিকটতম স্টেচন ব্যৱহাৰ কৰা হৈছে';

  @override
  String get searchByRoute => 'পথ অনুসৰি';

  @override
  String get searchByTrainNo => 'ৰেল নম্বৰ অনুসৰি';

  @override
  String get fieldFrom => 'কৰ পৰা';

  @override
  String get fieldTo => 'কলৈ';

  @override
  String get selectStation => 'স্টেচন বাছনি কৰক';

  @override
  String get searchTrains => 'ৰেল বিচাৰক';

  @override
  String get hintTrainNumber => 'ৰেল নম্বৰ দিয়ক (যেনে 12951)';

  @override
  String get hintSearchAny => 'ৰেলৰ নাম, নম্বৰ বা স্টেচন বিচাৰক';

  @override
  String get searchCityStationCode => 'নগৰ, স্টেচন বা কোড বিচাৰক';

  @override
  String get selectOrigin => 'যাত্ৰা আৰম্ভৰ স্টেচন বাছনি কৰক';

  @override
  String get selectDestination => 'গন্তব্য স্টেচন বাছনি কৰক';

  @override
  String get sectionRecent => 'শেহতীয়া';

  @override
  String get sectionPopular => 'জনপ্ৰিয় স্টেচন';

  @override
  String get filterAllTrains => 'সকলো ৰেল';

  @override
  String get filterNearby => 'কাষত';

  @override
  String get filterRunningStatus => 'চলাচলৰ স্থিতি';

  @override
  String get filterPnrStatus => 'PNR স্থিতি';

  @override
  String get filterLiveMap => 'লাইভ মেপ';

  @override
  String get filterExpress => 'এক্সপ্ৰেছ';

  @override
  String get filterSuperfast => 'চুপাৰফাস্ট';

  @override
  String get filterPassenger => 'পেছেঞ্জাৰ';

  @override
  String get filterOnTime => 'সময়মতে';

  @override
  String get filterDelayed => 'বিলম্ব';

  @override
  String countDepartures(int count) {
    return '$count টা আগন্তুক প্ৰস্থান';
  }

  @override
  String countNearYou(int count) {
    return 'আপোনাৰ কাষত $count টা ৰেল';
  }

  @override
  String countRunning(int count) {
    return '$count টা ৰেল চলি আছে';
  }

  @override
  String countOnRoute(int count, Object from, Object to) {
    return '$count টা ৰেল · $from → $to';
  }

  @override
  String countMatching(int count, Object query) {
    return '\"$query\" ৰ সৈতে মিলা $count টা';
  }

  @override
  String get noTrainsMatch => 'আপোনাৰ ফিল্টাৰৰ সৈতে কোনো ৰেল মিলা নাই';

  @override
  String get statusOnTime => 'সময়মতে';

  @override
  String statusDelayedMin(int minutes) {
    return '$minutes মিনিট বিলম্ব';
  }

  @override
  String platformAndEta(Object platform, int minutes) {
    return 'PF $platform · $minutes মিনিটত';
  }

  @override
  String get platformTba => 'প্লেটফৰ্ম ঘোষণা হোৱা নাই';

  @override
  String get liveGps => 'লাইভ GPS';

  @override
  String get pantry => 'পেণ্ট্ৰি';

  @override
  String get acThreeTier => 'AC 3-টিয়াৰ';

  @override
  String get acTwoTier => 'AC 2-টিয়াৰ';

  @override
  String scheduledDays(Object days) {
    return 'নিৰ্ধাৰিত · $days';
  }

  @override
  String get runsDaily => 'প্ৰতিদিনে';

  @override
  String get bookTitle => 'আপোনাৰ টিকট বুক কৰক';

  @override
  String get bookBody => 'সংৰক্ষণ চৰকাৰী IRCTC পৰ্টেলত হয়।';

  @override
  String get bookCta => 'IRCTC লৈ আগবাঢ়ক';

  @override
  String get bookSheetTitle => 'IRCTC ত বুক কৰক';

  @override
  String get bookSheetBody => 'টিকট বুকিং চৰকাৰী IRCTC পৰ্টেলত হয়।';

  @override
  String get bookOpening => 'IRCTC খোলা হৈছে — সংযোগ সোনকালে আহিব';

  @override
  String get cancel => 'বাতিল কৰক';

  @override
  String get tryAgain => 'পুনৰ চেষ্টা কৰক';

  @override
  String get gotIt => 'বুজিলোঁ';

  @override
  String get pnrHint => '10 সংখ্যাৰ PNR';

  @override
  String get pnrCheckCta => 'PNR স্থিতি চাওক';

  @override
  String get pnrNotFoundTitle => 'PNR পোৱা নগ\'ল';

  @override
  String pnrNotFoundBody(Object pnr) {
    return 'PNR $pnr বিচাৰি পোৱা নগ\'ল। আপোনাৰ টিকটত থকা 10 সংখ্যাৰ নম্বৰ পৰীক্ষা কৰি পুনৰ চেষ্টা কৰক।';
  }

  @override
  String get pnrSampleTip => 'পৰামৰ্শ: লাইভ উদাহৰণ চাবলৈ ওপৰৰ নমুনাত টেপ কৰক।';

  @override
  String get pnrSampleConfirmed => 'নিশ্চিত';

  @override
  String get pnrSampleWaitlisted => 'অপেক্ষা তালিকা';

  @override
  String get pnrSampleMixed => 'মিশ্ৰিত';

  @override
  String get checkBackLaterTitle => 'পিছত চাওক';

  @override
  String get pnrQuotaBody =>
      'মাহেকীয়া অনুৰোধ সীমা পূৰ্ণ হোৱাৰ ফলত লাইভ PNR তথ্য কিছু সময়ৰ বাবে উপলব্ধ নহয়। অনুগ্ৰহ কৰি পিছত চেষ্টা কৰক।';

  @override
  String get routeUnavailableTitle => 'পথ উপলব্ধ নহয়';

  @override
  String routeUnavailableGeneric(Object number) {
    return 'ৰেল $number ৰ পথ ল\'ড কৰিব পৰা নগ\'ল।';
  }

  @override
  String get routeUnavailableNotConnected =>
      'এই বিল্ডত লাইভ পথ ডেটা এতিয়াও সংযুক্ত হোৱা নাই।';

  @override
  String get routeUnavailableQuota =>
      'লাইভ ৰেলৱে ডেটা কিছু সময়ৰ বাবে উপলব্ধ নহয়। পিছত চাওক।';

  @override
  String routeUnavailableInconsistent(Object number) {
    return 'ৰেল $number ৰ পথ ডেটা অসংগত বুলি লাগিছে, সেয়ে দেখুওৱা হোৱা নাই।';
  }

  @override
  String liveTimelineStations(int count) {
    return 'লাইভ টাইমলাইন · $count টা স্টেচন';
  }

  @override
  String get destinationAlarm => 'গন্তব্য এলাৰ্ম';

  @override
  String get coachPosition => 'কোচৰ স্থান';

  @override
  String get setAlarm => 'এলাৰ্ম ছেট কৰক';

  @override
  String get unableToFetchRoute => 'পথ আনিব পৰা নগ\'ল। সংযোগ পৰীক্ষা কৰক।';

  @override
  String get settingsTitle => 'ছেটিংছ';

  @override
  String get sectionAppearance => 'ৰূপ';

  @override
  String get themeSystem => 'ছিষ্টেম';

  @override
  String get themeLight => 'লাইট';

  @override
  String get themeDark => 'ডাৰ্ক';

  @override
  String get appearanceHint =>
      'My Train কেনেকুৱা দেখা যাব বাছনি কৰক। \"ছিষ্টেম\" আপোনাৰ ডিভাইচৰ ছেটিং অনুসৰণ কৰে।';

  @override
  String get sectionLanguage => 'ভাষা';

  @override
  String get language => 'ভাষা';

  @override
  String get sectionAbout => 'এপৰ বিষয়ে';

  @override
  String aboutVersion(Object version) {
    return 'সংস্কৰণ $version';
  }

  @override
  String get aboutCoverage => 'কভাৰেজ';

  @override
  String aboutCoverageValue(Object count) {
    return '$count টা ৰেল স্টেচন';
  }

  @override
  String get aboutStationData => 'স্টেচন ডেটা';

  @override
  String get chooseLanguage => 'ভাষা বাছনি কৰক';

  @override
  String get chooseLanguageSubtitle =>
      'My Train কোন ভাষাত পঢ়িব বিচাৰে বাছনি কৰক।';

  @override
  String get submit => 'দাখিল কৰক';

  @override
  String languageChanged(Object language) {
    return 'ভাষা $language লৈ ছেট কৰা হ\'ল';
  }

  @override
  String platformNumber(Object platform) {
    return 'প্লেটফৰ্ম $platform';
  }

  @override
  String get weekdayLetters => 'দেও,সোম,মঙ্গল,বুধ,বৃহ,শুক্ৰ,শনি';

  @override
  String runsUntil(Object date) {
    return '$date লৈকে চলে';
  }
}
