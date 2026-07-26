// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Bengali Bangla (`bn`).
class L10nBn extends L10n {
  L10nBn([String locale = 'bn']) : super(locale);

  @override
  String get appName => 'My Train';

  @override
  String get navTrack => 'ট্র্যাক';

  @override
  String get navPnr => 'PNR';

  @override
  String get navBook => 'বুকিং';

  @override
  String get navProfile => 'প্রোফাইল';

  @override
  String get heroTitle => 'আপনার পরবর্তী যাত্রা ট্র্যাক করুন';

  @override
  String get heroSubtitle =>
      'সারা ভারতে লাইভ স্ট্যাটাস, PNR ও প্ল্যাটফর্ম তথ্য';

  @override
  String get nearestStation => 'নিকটতম স্টেশন';

  @override
  String get usingNearestStation => 'নিকটতম স্টেশন ব্যবহার করা হচ্ছে';

  @override
  String get searchByRoute => 'রুট অনুযায়ী';

  @override
  String get searchByTrainNo => 'ট্রেন নম্বর অনুযায়ী';

  @override
  String get fieldFrom => 'কোথা থেকে';

  @override
  String get fieldTo => 'কোথায়';

  @override
  String get selectStation => 'স্টেশন নির্বাচন করুন';

  @override
  String get searchTrains => 'ট্রেন খুঁজুন';

  @override
  String get hintTrainNumber => 'ট্রেন নম্বর লিখুন (যেমন 12951)';

  @override
  String get hintSearchAny => 'ট্রেনের নাম, নম্বর বা স্টেশন খুঁজুন';

  @override
  String get searchCityStationCode => 'শহর, স্টেশন বা কোড খুঁজুন';

  @override
  String get selectOrigin => 'যাত্রা শুরুর স্টেশন নির্বাচন করুন';

  @override
  String get selectDestination => 'গন্তব্য স্টেশন নির্বাচন করুন';

  @override
  String get sectionRecent => 'সাম্প্রতিক';

  @override
  String get sectionPopular => 'জনপ্রিয় স্টেশন';

  @override
  String get filterAllTrains => 'সব ট্রেন';

  @override
  String get filterNearby => 'কাছাকাছি';

  @override
  String get filterRunningStatus => 'চলাচলের অবস্থা';

  @override
  String get filterPnrStatus => 'PNR অবস্থা';

  @override
  String get filterLiveMap => 'লাইভ ম্যাপ';

  @override
  String get filterExpress => 'এক্সপ্রেস';

  @override
  String get filterSuperfast => 'সুপারফাস্ট';

  @override
  String get filterPassenger => 'প্যাসেঞ্জার';

  @override
  String get filterOnTime => 'সময়মতো';

  @override
  String get filterDelayed => 'বিলম্বিত';

  @override
  String countDepartures(int count) {
    return '$countটি আসন্ন প্রস্থান';
  }

  @override
  String countNearYou(int count) {
    return 'আপনার কাছে $countটি ট্রেন';
  }

  @override
  String countRunning(int count) {
    return '$countটি ট্রেন চলছে';
  }

  @override
  String countOnRoute(int count, Object from, Object to) {
    return '$countটি ট্রেন · $from → $to';
  }

  @override
  String countMatching(int count, Object query) {
    return '\"$query\" এর সাথে মিলছে $countটি';
  }

  @override
  String get noTrainsMatch => 'আপনার ফিল্টারের সাথে কোনো ট্রেন মিলছে না';

  @override
  String get statusOnTime => 'সময়মতো';

  @override
  String statusDelayedMin(int minutes) {
    return '$minutes মিনিট বিলম্ব';
  }

  @override
  String platformAndEta(Object platform, int minutes) {
    return 'PF $platform · $minutes মিনিটে';
  }

  @override
  String get platformTba => 'প্ল্যাটফর্ম ঘোষণা হয়নি';

  @override
  String get liveGps => 'লাইভ GPS';

  @override
  String get pantry => 'প্যান্ট্রি';

  @override
  String get acThreeTier => 'AC 3-টিয়ার';

  @override
  String get acTwoTier => 'AC 2-টিয়ার';

  @override
  String scheduledDays(Object days) {
    return 'নির্ধারিত · $days';
  }

  @override
  String get runsDaily => 'প্রতিদিন';

  @override
  String get bookTitle => 'আপনার টিকিট বুক করুন';

  @override
  String get bookBody => 'সংরক্ষণ সরকারি IRCTC পোর্টালে হয়।';

  @override
  String get bookCta => 'IRCTC-তে এগিয়ে যান';

  @override
  String get bookSheetTitle => 'IRCTC-তে বুক করুন';

  @override
  String get bookSheetBody => 'টিকিট বুকিং সরকারি IRCTC পোর্টালে হয়।';

  @override
  String get bookOpening => 'IRCTC খোলা হচ্ছে — সংযুক্তি শিগগিরই';

  @override
  String get cancel => 'বাতিল';

  @override
  String get tryAgain => 'আবার চেষ্টা করুন';

  @override
  String get gotIt => 'বুঝেছি';

  @override
  String get pnrHint => '১০ সংখ্যার PNR';

  @override
  String get pnrCheckCta => 'PNR অবস্থা দেখুন';

  @override
  String get pnrNotFoundTitle => 'PNR পাওয়া যায়নি';

  @override
  String pnrNotFoundBody(Object pnr) {
    return 'PNR $pnr খুঁজে পাওয়া যায়নি। আপনার টিকিটের ১০ সংখ্যার নম্বর যাচাই করে আবার চেষ্টা করুন।';
  }

  @override
  String get pnrSampleTip => 'টিপ: লাইভ উদাহরণ দেখতে উপরের নমুনায় ট্যাপ করুন।';

  @override
  String get pnrSampleConfirmed => 'নিশ্চিত';

  @override
  String get pnrSampleWaitlisted => 'অপেক্ষমাণ';

  @override
  String get pnrSampleMixed => 'মিশ্র';

  @override
  String get checkBackLaterTitle => 'পরে দেখুন';

  @override
  String get pnrQuotaBody =>
      'মাসিক অনুরোধ সীমা শেষ হওয়ায় লাইভ PNR তথ্য সাময়িকভাবে অনুপলব্ধ। পরে চেষ্টা করুন।';

  @override
  String get routeUnavailableTitle => 'রুট অনুপলব্ধ';

  @override
  String routeUnavailableGeneric(Object number) {
    return 'ট্রেন $number এর রুট লোড করা যায়নি।';
  }

  @override
  String get routeUnavailableNotConnected =>
      'এই বিল্ডে লাইভ রুট ডেটা এখনও সংযুক্ত নয়।';

  @override
  String get routeUnavailableQuota =>
      'লাইভ রেলওয়ে ডেটা সাময়িকভাবে অনুপলব্ধ। পরে দেখুন।';

  @override
  String routeUnavailableInconsistent(Object number) {
    return 'ট্রেন $number এর রুট ডেটা অসঙ্গত মনে হচ্ছে, তাই দেখানো হচ্ছে না।';
  }

  @override
  String liveTimelineStations(int count) {
    return 'লাইভ টাইমলাইন · $countটি স্টেশন';
  }

  @override
  String get destinationAlarm => 'গন্তব্য অ্যালার্ম';

  @override
  String get coachPosition => 'কোচের অবস্থান';

  @override
  String get setAlarm => 'অ্যালার্ম সেট করুন';

  @override
  String get unableToFetchRoute => 'রুট আনা যায়নি। সংযোগ পরীক্ষা করুন।';

  @override
  String get settingsTitle => 'সেটিংস';

  @override
  String get sectionAppearance => 'উপস্থাপনা';

  @override
  String get themeSystem => 'সিস্টেম';

  @override
  String get themeLight => 'লাইট';

  @override
  String get themeDark => 'ডার্ক';

  @override
  String get appearanceHint =>
      'My Train কেমন দেখাবে তা বাছুন। \"সিস্টেম\" আপনার ডিভাইসের সেটিং অনুসরণ করে।';

  @override
  String get sectionLanguage => 'ভাষা';

  @override
  String get language => 'ভাষা';

  @override
  String get sectionAbout => 'অ্যাপ সম্পর্কে';

  @override
  String aboutVersion(Object version) {
    return 'সংস্করণ $version';
  }

  @override
  String get aboutCoverage => 'কভারেজ';

  @override
  String aboutCoverageValue(Object count) {
    return '$countটি রেলস্টেশন';
  }

  @override
  String get aboutStationData => 'স্টেশন ডেটা';

  @override
  String get chooseLanguage => 'ভাষা নির্বাচন করুন';

  @override
  String get chooseLanguageSubtitle =>
      'My Train কোন ভাষায় পড়তে চান তা বাছুন।';

  @override
  String get submit => 'জমা দিন';

  @override
  String languageChanged(Object language) {
    return 'ভাষা $language এ সেট করা হয়েছে';
  }

  @override
  String platformNumber(Object platform) {
    return 'প্ল্যাটফর্ম $platform';
  }

  @override
  String get weekdayLetters => 'রবি,সোম,মঙ্গল,বুধ,বৃহ,শুক্র,শনি';

  @override
  String runsUntil(Object date) {
    return '$date পর্যন্ত চলে';
  }
}
