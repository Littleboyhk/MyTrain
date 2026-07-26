// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Marathi (`mr`).
class L10nMr extends L10n {
  L10nMr([String locale = 'mr']) : super(locale);

  @override
  String get appName => 'My Train';

  @override
  String get navTrack => 'ट्रॅक';

  @override
  String get navPnr => 'PNR';

  @override
  String get navBook => 'बुकिंग';

  @override
  String get navProfile => 'प्रोफाइल';

  @override
  String get heroTitle => 'तुमचा पुढील प्रवास ट्रॅक करा';

  @override
  String get heroSubtitle =>
      'संपूर्ण भारतात लाइव्ह स्थिती, PNR आणि प्लॅटफॉर्म माहिती';

  @override
  String get nearestStation => 'जवळचे स्थानक';

  @override
  String get usingNearestStation => 'जवळचे स्थानक वापरले जात आहे';

  @override
  String get searchByRoute => 'मार्गानुसार';

  @override
  String get searchByTrainNo => 'गाडी क्रमांकानुसार';

  @override
  String get fieldFrom => 'कुठून';

  @override
  String get fieldTo => 'कुठवर';

  @override
  String get selectStation => 'स्थानक निवडा';

  @override
  String get searchTrains => 'गाड्या शोधा';

  @override
  String get hintTrainNumber => 'गाडी क्रमांक टाका (उदा. 12951)';

  @override
  String get hintSearchAny => 'गाडीचे नाव, क्रमांक किंवा स्थानक शोधा';

  @override
  String get searchCityStationCode => 'शहर, स्थानक किंवा कोड शोधा';

  @override
  String get selectOrigin => 'प्रस्थान स्थानक निवडा';

  @override
  String get selectDestination => 'गंतव्य स्थानक निवडा';

  @override
  String get sectionRecent => 'अलीकडील';

  @override
  String get sectionPopular => 'लोकप्रिय स्थानके';

  @override
  String get filterAllTrains => 'सर्व गाड्या';

  @override
  String get filterNearby => 'जवळपास';

  @override
  String get filterRunningStatus => 'धावण्याची स्थिती';

  @override
  String get filterPnrStatus => 'PNR स्थिती';

  @override
  String get filterLiveMap => 'लाइव्ह नकाशा';

  @override
  String get filterExpress => 'एक्सप्रेस';

  @override
  String get filterSuperfast => 'सुपरफास्ट';

  @override
  String get filterPassenger => 'पॅसेंजर';

  @override
  String get filterOnTime => 'वेळेवर';

  @override
  String get filterDelayed => 'उशीर';

  @override
  String countDepartures(int count) {
    return '$count आगामी प्रस्थाने';
  }

  @override
  String countNearYou(int count) {
    return 'तुमच्या जवळ $count गाड्या';
  }

  @override
  String countRunning(int count) {
    return '$count गाड्या धावत आहेत';
  }

  @override
  String countOnRoute(int count, Object from, Object to) {
    return '$count गाड्या · $from → $to';
  }

  @override
  String countMatching(int count, Object query) {
    return '\"$query\" शी जुळणाऱ्या $count';
  }

  @override
  String get noTrainsMatch => 'तुमच्या फिल्टरशी कोणतीही गाडी जुळत नाही';

  @override
  String get statusOnTime => 'वेळेवर';

  @override
  String statusDelayedMin(int minutes) {
    return '$minutes मिनिटे उशीर';
  }

  @override
  String platformAndEta(Object platform, int minutes) {
    return 'PF $platform · $minutes मिनिटांत';
  }

  @override
  String get platformTba => 'प्लॅटफॉर्म जाहीर नाही';

  @override
  String get liveGps => 'लाइव्ह GPS';

  @override
  String get pantry => 'पँट्री';

  @override
  String get acThreeTier => 'AC 3-टियर';

  @override
  String get acTwoTier => 'AC 2-टियर';

  @override
  String scheduledDays(Object days) {
    return 'नियोजित · $days';
  }

  @override
  String get runsDaily => 'दररोज';

  @override
  String get bookTitle => 'तुमचे तिकीट बुक करा';

  @override
  String get bookBody => 'आरक्षण अधिकृत IRCTC पोर्टलवर होते.';

  @override
  String get bookCta => 'IRCTC वर सुरू ठेवा';

  @override
  String get bookSheetTitle => 'IRCTC वर बुक करा';

  @override
  String get bookSheetBody => 'तिकीट बुकिंग अधिकृत IRCTC पोर्टलवर होते.';

  @override
  String get bookOpening => 'IRCTC उघडत आहे — एकत्रीकरण लवकरच';

  @override
  String get cancel => 'रद्द करा';

  @override
  String get tryAgain => 'पुन्हा प्रयत्न करा';

  @override
  String get gotIt => 'समजले';

  @override
  String get pnrHint => '10 अंकी PNR';

  @override
  String get pnrCheckCta => 'PNR स्थिती तपासा';

  @override
  String get pnrNotFoundTitle => 'PNR आढळले नाही';

  @override
  String pnrNotFoundBody(Object pnr) {
    return 'PNR $pnr सापडले नाही. तुमच्या तिकिटावरील 10 अंकी क्रमांक तपासा आणि पुन्हा प्रयत्न करा.';
  }

  @override
  String get pnrSampleTip =>
      'टीप: लाइव्ह उदाहरण पाहण्यासाठी वरील नमुन्यावर टॅप करा.';

  @override
  String get pnrSampleConfirmed => 'निश्चित';

  @override
  String get pnrSampleWaitlisted => 'प्रतीक्षा यादी';

  @override
  String get pnrSampleMixed => 'मिश्र';

  @override
  String get checkBackLaterTitle => 'नंतर पहा';

  @override
  String get pnrQuotaBody =>
      'मासिक विनंती मर्यादा संपल्याने लाइव्ह PNR माहिती तात्पुरती उपलब्ध नाही. कृपया नंतर प्रयत्न करा.';

  @override
  String get routeUnavailableTitle => 'मार्ग उपलब्ध नाही';

  @override
  String routeUnavailableGeneric(Object number) {
    return 'गाडी $number चा मार्ग लोड होऊ शकला नाही.';
  }

  @override
  String get routeUnavailableNotConnected =>
      'या बिल्डमध्ये लाइव्ह मार्ग डेटा अद्याप जोडलेला नाही.';

  @override
  String get routeUnavailableQuota =>
      'लाइव्ह रेल्वे डेटा तात्पुरता उपलब्ध नाही. कृपया नंतर पहा.';

  @override
  String routeUnavailableInconsistent(Object number) {
    return 'गाडी $number चा मार्ग डेटा विसंगत वाटतो, म्हणून दाखवला जात नाही.';
  }

  @override
  String liveTimelineStations(int count) {
    return 'लाइव्ह टाइमलाइन · $count स्थानके';
  }

  @override
  String get destinationAlarm => 'गंतव्य गजर';

  @override
  String get coachPosition => 'डबा स्थिती';

  @override
  String get setAlarm => 'गजर लावा';

  @override
  String get unableToFetchRoute => 'मार्ग मिळवता आला नाही. कनेक्शन तपासा.';

  @override
  String get settingsTitle => 'सेटिंग्ज';

  @override
  String get sectionAppearance => 'देखावा';

  @override
  String get themeSystem => 'सिस्टम';

  @override
  String get themeLight => 'लाइट';

  @override
  String get themeDark => 'डार्क';

  @override
  String get appearanceHint =>
      'My Train कसे दिसावे ते निवडा. \"सिस्टम\" तुमच्या डिव्हाइसची सेटिंग पाळते.';

  @override
  String get sectionLanguage => 'भाषा';

  @override
  String get language => 'भाषा';

  @override
  String get sectionAbout => 'अॅपविषयी';

  @override
  String aboutVersion(Object version) {
    return 'आवृत्ती $version';
  }

  @override
  String get aboutCoverage => 'व्याप्ती';

  @override
  String aboutCoverageValue(Object count) {
    return '$count रेल्वे स्थानके';
  }

  @override
  String get aboutStationData => 'स्थानक डेटा';

  @override
  String get chooseLanguage => 'भाषा निवडा';

  @override
  String get chooseLanguageSubtitle =>
      'My Train कोणत्या भाषेत वाचायचे ते निवडा.';

  @override
  String get submit => 'सबमिट करा';

  @override
  String languageChanged(Object language) {
    return 'भाषा $language वर सेट केली';
  }

  @override
  String platformNumber(Object platform) {
    return 'प्लॅटफॉर्म $platform';
  }

  @override
  String get weekdayLetters => 'रवि,सोम,मंगळ,बुध,गुरु,शुक्र,शनि';

  @override
  String runsUntil(Object date) {
    return '$date पर्यंत धावते';
  }
}
