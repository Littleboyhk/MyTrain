// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Hindi (`hi`).
class L10nHi extends L10n {
  L10nHi([String locale = 'hi']) : super(locale);

  @override
  String get appName => 'My Train';

  @override
  String get navTrack => 'ट्रैक';

  @override
  String get navPnr => 'PNR';

  @override
  String get navBook => 'बुकिंग';

  @override
  String get navProfile => 'प्रोफ़ाइल';

  @override
  String get heroTitle => 'अपनी अगली यात्रा ट्रैक करें';

  @override
  String get heroSubtitle =>
      'पूरे भारत में लाइव स्टेटस, PNR और प्लेटफ़ॉर्म जानकारी';

  @override
  String get nearestStation => 'निकटतम स्टेशन';

  @override
  String get usingNearestStation => 'निकटतम स्टेशन का उपयोग हो रहा है';

  @override
  String get searchByRoute => 'रूट से';

  @override
  String get searchByTrainNo => 'ट्रेन नंबर से';

  @override
  String get fieldFrom => 'कहाँ से';

  @override
  String get fieldTo => 'कहाँ तक';

  @override
  String get selectStation => 'स्टेशन चुनें';

  @override
  String get searchTrains => 'ट्रेनें खोजें';

  @override
  String get hintTrainNumber => 'ट्रेन नंबर दर्ज करें (जैसे 12951)';

  @override
  String get hintSearchAny => 'ट्रेन का नाम, नंबर या स्टेशन खोजें';

  @override
  String get searchCityStationCode => 'शहर, स्टेशन या कोड खोजें';

  @override
  String get selectOrigin => 'प्रस्थान स्टेशन चुनें';

  @override
  String get selectDestination => 'गंतव्य स्टेशन चुनें';

  @override
  String get sectionRecent => 'हाल के';

  @override
  String get sectionPopular => 'लोकप्रिय स्टेशन';

  @override
  String get filterAllTrains => 'सभी ट्रेनें';

  @override
  String get filterNearby => 'आसपास';

  @override
  String get filterRunningStatus => 'रनिंग स्टेटस';

  @override
  String get filterPnrStatus => 'PNR स्टेटस';

  @override
  String get filterLiveMap => 'लाइव मैप';

  @override
  String get filterExpress => 'एक्सप्रेस';

  @override
  String get filterSuperfast => 'सुपरफास्ट';

  @override
  String get filterPassenger => 'पैसेंजर';

  @override
  String get filterOnTime => 'समय पर';

  @override
  String get filterDelayed => 'देरी से';

  @override
  String countDepartures(int count) {
    return '$count आगामी प्रस्थान';
  }

  @override
  String countNearYou(int count) {
    return 'आपके पास $count ट्रेनें';
  }

  @override
  String countRunning(int count) {
    return '$count ट्रेनें चल रही हैं';
  }

  @override
  String countOnRoute(int count, Object from, Object to) {
    return '$count ट्रेनें · $from → $to';
  }

  @override
  String countMatching(int count, Object query) {
    return '\"$query\" से मेल खाती $count';
  }

  @override
  String get sectionPersonal => 'PERSONAL';

  @override
  String get sectionSpot => 'SPOT SETTINGS';

  @override
  String get sectionSpeedometer => 'SPEEDOMETER SETTINGS';

  @override
  String get sectionAlarm => 'ALARM SETTINGS';

  @override
  String get timeSettings => 'Time settings';

  @override
  String get timeSettingsHint => 'Show times as AM/PM instead of 24-hour';

  @override
  String get insideTrainSetting => 'Are you inside train option';

  @override
  String get insideTrainSettingHint =>
      'Suggest sharing your location when a journey opens';

  @override
  String get spotNotifications => 'Spot notifications';

  @override
  String get spotNotificationsHint =>
      'Your location as a standing notification';

  @override
  String get spotNotificationsUnsupported =>
      'Not available in this build — needs a notification plugin, and has no web equivalent';

  @override
  String get speedometerSetting => 'Speedometer (Beta)';

  @override
  String get speedometerSettingHint => 'Show live GPS speed while tracking';

  @override
  String get speedometerRequiresGps =>
      'Appears on the tracking screen once you start sharing your location in GPS mode, which is where the speed reading comes from.';

  @override
  String get alarmTone => 'Alarm tone';

  @override
  String alarmToneChanged(String tone) {
    return 'Alarm tone set to $tone';
  }

  @override
  String get alarmTonePlaybackNote =>
      'Select an alarm tone to preview and set your preferred sound.';

  @override
  String get noTrainsMatch => 'आपके फ़िल्टर से कोई ट्रेन मेल नहीं खाती';

  @override
  String trainNotFound(String number) {
    return 'Train $number not found';
  }

  @override
  String get trainNotFoundHint => 'Check the number and try again';

  @override
  String get trainLookupFailed => 'Couldn\'t check right now';

  @override
  String get trainLookupFailedHint =>
      'Something went wrong reaching the railway data. Try again in a moment.';

  @override
  String searchingTrain(String number) {
    return 'Looking up train $number…';
  }

  @override
  String get statusOnTime => 'समय पर';

  @override
  String statusDelayedMin(int minutes) {
    return '$minutes मिनट देरी';
  }

  @override
  String platformAndEta(Object platform, int minutes) {
    return 'PF $platform · $minutes मिनट में';
  }

  @override
  String get platformTba => 'प्लेटफ़ॉर्म घोषित नहीं';

  @override
  String get liveGps => 'लाइव GPS';

  @override
  String get pantry => 'पैंट्री';

  @override
  String get acThreeTier => 'AC 3-टियर';

  @override
  String get acTwoTier => 'AC 2-टियर';

  @override
  String scheduledDays(Object days) {
    return 'निर्धारित · $days';
  }

  @override
  String get runsDaily => 'रोज़';

  @override
  String get bookTitle => 'अपनी टिकट बुक करें';

  @override
  String get bookBody => 'आरक्षण आधिकारिक IRCTC पोर्टल पर होता है।';

  @override
  String get bookCta => 'IRCTC पर जारी रखें';

  @override
  String get bookSheetTitle => 'IRCTC पर बुक करें';

  @override
  String get bookSheetBody => 'टिकट बुकिंग आधिकारिक IRCTC पोर्टल पर होती है।';

  @override
  String get bookOpening => 'IRCTC खोल रहे हैं — एकीकरण जल्द आ रहा है';

  @override
  String get cancel => 'रद्द करें';

  @override
  String get tryAgain => 'फिर कोशिश करें';

  @override
  String get gotIt => 'समझ गया';

  @override
  String get pnrHint => '10 अंकों का PNR';

  @override
  String get pnrCheckCta => 'PNR स्टेटस देखें';

  @override
  String get pnrNotFoundTitle => 'PNR नहीं मिला';

  @override
  String pnrNotFoundBody(Object pnr) {
    return 'हमें PNR $pnr नहीं मिला। अपनी टिकट पर 10 अंकों का नंबर जाँचें और फिर कोशिश करें।';
  }

  @override
  String get pnrSampleTip =>
      'सुझाव: लाइव उदाहरण देखने के लिए ऊपर दिए नमूने पर टैप करें।';

  @override
  String get pnrSampleConfirmed => 'कन्फर्म';

  @override
  String get pnrSampleWaitlisted => 'वेटलिस्ट';

  @override
  String get pnrSampleMixed => 'मिश्रित';

  @override
  String get checkBackLaterTitle => 'बाद में देखें';

  @override
  String get pnrQuotaBody =>
      'मासिक अनुरोध सीमा पूरी होने के कारण लाइव PNR जानकारी अस्थायी रूप से उपलब्ध नहीं है। कृपया बाद में कोशिश करें।';

  @override
  String get routeUnavailableTitle => 'रूट उपलब्ध नहीं';

  @override
  String routeUnavailableGeneric(Object number) {
    return 'ट्रेन $number का रूट लोड नहीं हो सका।';
  }

  @override
  String get routeUnavailableNotConnected =>
      'इस बिल्ड में लाइव रूट डेटा अभी कनेक्ट नहीं है।';

  @override
  String get routeUnavailableQuota =>
      'लाइव रेलवे डेटा अस्थायी रूप से उपलब्ध नहीं है। कृपया बाद में देखें।';

  @override
  String routeUnavailableInconsistent(Object number) {
    return 'ट्रेन $number का रूट डेटा असंगत लग रहा है, इसलिए इसे नहीं दिखाया जा रहा।';
  }

  @override
  String liveTimelineStations(int count) {
    return 'लाइव टाइमलाइन · $count स्टेशन';
  }

  @override
  String get destinationAlarm => 'गंतव्य अलार्म';

  @override
  String get coachPosition => 'कोच पोज़िशन';

  @override
  String get setAlarm => 'अलार्म सेट करें';

  @override
  String get unableToFetchRoute =>
      'रूट प्राप्त नहीं हो सका। कृपया कनेक्शन जाँचें।';

  @override
  String get settingsTitle => 'सेटिंग्स';

  @override
  String get sectionAppearance => 'दिखावट';

  @override
  String get themeSystem => 'सिस्टम';

  @override
  String get themeLight => 'लाइट';

  @override
  String get themeDark => 'डार्क';

  @override
  String get appearanceHint =>
      'चुनें कि My Train कैसा दिखे। \"सिस्टम\" आपके डिवाइस की सेटिंग का पालन करता है।';

  @override
  String get sectionLanguage => 'भाषा';

  @override
  String get language => 'भाषा';

  @override
  String get sectionAbout => 'ऐप के बारे में';

  @override
  String aboutVersion(Object version) {
    return 'संस्करण $version';
  }

  @override
  String get aboutCoverage => 'कवरेज';

  @override
  String aboutCoverageValue(Object count) {
    return '$count रेलवे स्टेशन';
  }

  @override
  String get aboutStationData => 'स्टेशन डेटा';

  @override
  String get chooseLanguage => 'भाषा चुनें';

  @override
  String get chooseLanguageSubtitle =>
      'चुनें कि आप My Train किस भाषा में पढ़ना चाहेंगे।';

  @override
  String get submit => 'सबमिट करें';

  @override
  String languageChanged(Object language) {
    return 'भाषा $language पर सेट की गई';
  }

  @override
  String platformNumber(Object platform) {
    return 'प्लेटफ़ॉर्म $platform';
  }

  @override
  String get weekdayLetters => 'रवि,सोम,मंगल,बुध,गुरु,शुक्र,शनि';

  @override
  String runsUntil(Object date) {
    return '$date तक चलती है';
  }
}
