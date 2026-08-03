// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Tamil (`ta`).
class L10nTa extends L10n {
  L10nTa([String locale = 'ta']) : super(locale);

  @override
  String get appName => 'My Train';

  @override
  String get navTrack => 'கண்காணி';

  @override
  String get navPnr => 'PNR';

  @override
  String get navBook => 'முன்பதிவு';

  @override
  String get navProfile => 'சுயவிவரம்';

  @override
  String get heroTitle => 'உங்கள் அடுத்த பயணத்தைக் கண்காணிக்கவும்';

  @override
  String get heroSubtitle =>
      'இந்தியா முழுவதும் நேரலை நிலை, PNR மற்றும் நடைமேடை தகவல்';

  @override
  String get nearestStation => 'அருகிலுள்ள நிலையம்';

  @override
  String get usingNearestStation => 'அருகிலுள்ள நிலையம் பயன்படுத்தப்படுகிறது';

  @override
  String get searchByRoute => 'வழித்தடம் மூலம்';

  @override
  String get searchByTrainNo => 'ரயில் எண் மூலம்';

  @override
  String get fieldFrom => 'எங்கிருந்து';

  @override
  String get fieldTo => 'எங்கு வரை';

  @override
  String get selectStation => 'நிலையத்தைத் தேர்ந்தெடுக்கவும்';

  @override
  String get searchTrains => 'ரயில்களைத் தேடு';

  @override
  String get hintTrainNumber => 'ரயில் எண்ணை உள்ளிடவும் (எ.கா. 12951)';

  @override
  String get hintSearchAny => 'ரயில் பெயர், எண் அல்லது நிலையத்தைத் தேடவும்';

  @override
  String get searchCityStationCode =>
      'நகரம், நிலையம் அல்லது குறியீட்டைத் தேடவும்';

  @override
  String get selectOrigin => 'புறப்படும் நிலையத்தைத் தேர்ந்தெடுக்கவும்';

  @override
  String get selectDestination => 'சேரும் நிலையத்தைத் தேர்ந்தெடுக்கவும்';

  @override
  String get sectionRecent => 'சமீபத்தியவை';

  @override
  String get sectionPopular => 'பிரபல நிலையங்கள்';

  @override
  String get filterAllTrains => 'அனைத்து ரயில்கள்';

  @override
  String get filterNearby => 'அருகில்';

  @override
  String get filterRunningStatus => 'இயக்க நிலை';

  @override
  String get filterPnrStatus => 'PNR நிலை';

  @override
  String get filterLiveMap => 'நேரலை வரைபடம்';

  @override
  String get filterExpress => 'எக்ஸ்பிரஸ்';

  @override
  String get filterSuperfast => 'சூப்பர்ஃபாஸ்ட்';

  @override
  String get filterPassenger => 'பாசஞ்சர்';

  @override
  String get filterOnTime => 'சரியான நேரத்தில்';

  @override
  String get filterDelayed => 'தாமதம்';

  @override
  String countDepartures(int count) {
    return '$count வரவிருக்கும் புறப்பாடுகள்';
  }

  @override
  String countNearYou(int count) {
    return 'உங்கள் அருகில் $count ரயில்கள்';
  }

  @override
  String countRunning(int count) {
    return '$count ரயில்கள் இயங்குகின்றன';
  }

  @override
  String countOnRoute(int count, Object from, Object to) {
    return '$count ரயில்கள் · $from → $to';
  }

  @override
  String countMatching(int count, Object query) {
    return '\"$query\" உடன் பொருந்தும் $count';
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
  String get noTrainsMatch => 'உங்கள் வடிகட்டிகளுக்கு ரயில்கள் பொருந்தவில்லை';

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
  String get statusOnTime => 'சரியான நேரத்தில்';

  @override
  String statusDelayedMin(int minutes) {
    return '$minutes நிமிடம் தாமதம்';
  }

  @override
  String platformAndEta(Object platform, int minutes) {
    return 'PF $platform · $minutes நிமிடத்தில்';
  }

  @override
  String get platformTba => 'நடைமேடை அறிவிக்கப்படவில்லை';

  @override
  String get liveGps => 'நேரலை GPS';

  @override
  String get pantry => 'உணவுப் பெட்டி';

  @override
  String get acThreeTier => 'AC 3-டயர்';

  @override
  String get acTwoTier => 'AC 2-டயர்';

  @override
  String scheduledDays(Object days) {
    return 'திட்டமிடப்பட்டது · $days';
  }

  @override
  String get runsDaily => 'தினமும்';

  @override
  String get bookTitle => 'உங்கள் டிக்கெட்டை முன்பதிவு செய்யுங்கள்';

  @override
  String get bookBody =>
      'முன்பதிவு அதிகாரப்பூர்வ IRCTC போர்ட்டலில் நடைபெறுகிறது.';

  @override
  String get bookCta => 'IRCTC-க்குத் தொடரவும்';

  @override
  String get bookSheetTitle => 'IRCTC-யில் முன்பதிவு';

  @override
  String get bookSheetBody =>
      'டிக்கெட் முன்பதிவு அதிகாரப்பூர்வ IRCTC போர்ட்டலில் நடைபெறுகிறது.';

  @override
  String get bookOpening => 'IRCTC திறக்கப்படுகிறது — ஒருங்கிணைப்பு விரைவில்';

  @override
  String get cancel => 'ரத்து செய்';

  @override
  String get tryAgain => 'மீண்டும் முயற்சி';

  @override
  String get gotIt => 'புரிந்தது';

  @override
  String get pnrHint => '10 இலக்க PNR';

  @override
  String get pnrCheckCta => 'PNR நிலையைச் சரிபார்';

  @override
  String get pnrNotFoundTitle => 'PNR கண்டறியப்படவில்லை';

  @override
  String pnrNotFoundBody(Object pnr) {
    return 'PNR $pnr கண்டறிய முடியவில்லை. உங்கள் டிக்கெட்டில் உள்ள 10 இலக்க எண்ணைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.';
  }

  @override
  String get pnrSampleTip =>
      'குறிப்பு: நேரலை எடுத்துக்காட்டைக் காண மேலே உள்ள மாதிரியைத் தட்டவும்.';

  @override
  String get pnrSampleConfirmed => 'உறுதி';

  @override
  String get pnrSampleWaitlisted => 'காத்திருப்பு';

  @override
  String get pnrSampleMixed => 'கலவை';

  @override
  String get checkBackLaterTitle => 'பிறகு பார்க்கவும்';

  @override
  String get pnrQuotaBody =>
      'மாதாந்திர கோரிக்கை வரம்பு எட்டியதால் நேரலை PNR தகவல் தற்காலிகமாகக் கிடைக்கவில்லை. பிறகு முயற்சிக்கவும்.';

  @override
  String get routeUnavailableTitle => 'வழித்தடம் கிடைக்கவில்லை';

  @override
  String routeUnavailableGeneric(Object number) {
    return 'ரயில் $number-க்கான வழித்தடத்தை ஏற்ற முடியவில்லை.';
  }

  @override
  String get routeUnavailableNotConnected =>
      'இந்த பதிப்பில் நேரலை வழித்தட தரவு இணைக்கப்படவில்லை.';

  @override
  String get routeUnavailableQuota =>
      'நேரலை ரயில்வே தரவு தற்காலிகமாகக் கிடைக்கவில்லை. பிறகு பார்க்கவும்.';

  @override
  String routeUnavailableInconsistent(Object number) {
    return 'ரயில் $number-க்கான வழித்தட தரவு முரணாகத் தெரிகிறது, எனவே காட்டப்படவில்லை.';
  }

  @override
  String liveTimelineStations(int count) {
    return 'நேரலை காலவரிசை · $count நிலையங்கள்';
  }

  @override
  String get destinationAlarm => 'சேரும் இட அலாரம்';

  @override
  String get coachPosition => 'பெட்டி நிலை';

  @override
  String get setAlarm => 'அலாரம் அமை';

  @override
  String get unableToFetchRoute =>
      'வழித்தடத்தைப் பெற முடியவில்லை. இணைப்பைச் சரிபார்க்கவும்.';

  @override
  String get settingsTitle => 'அமைப்புகள்';

  @override
  String get sectionAppearance => 'தோற்றம்';

  @override
  String get themeSystem => 'சிஸ்டம்';

  @override
  String get themeLight => 'ஒளி';

  @override
  String get themeDark => 'இருள்';

  @override
  String get appearanceHint =>
      'My Train எப்படித் தோன்ற வேண்டும் என்பதைத் தேர்வுசெய்யவும். \"சிஸ்டம்\" உங்கள் சாதன அமைப்பைப் பின்பற்றும்.';

  @override
  String get sectionLanguage => 'மொழி';

  @override
  String get language => 'மொழி';

  @override
  String get sectionAbout => 'பயன்பாட்டு விவரம்';

  @override
  String aboutVersion(Object version) {
    return 'பதிப்பு $version';
  }

  @override
  String get aboutCoverage => 'பரப்பளவு';

  @override
  String aboutCoverageValue(Object count) {
    return '$count ரயில் நிலையங்கள்';
  }

  @override
  String get aboutStationData => 'நிலையத் தரவு';

  @override
  String get chooseLanguage => 'மொழியைத் தேர்ந்தெடுக்கவும்';

  @override
  String get chooseLanguageSubtitle =>
      'My Train-ஐ எந்த மொழியில் படிக்க விரும்புகிறீர்கள் என்பதைத் தேர்வுசெய்யவும்.';

  @override
  String get submit => 'சமர்ப்பி';

  @override
  String languageChanged(Object language) {
    return 'மொழி $language ஆக அமைக்கப்பட்டது';
  }

  @override
  String platformNumber(Object platform) {
    return 'நடைமேடை $platform';
  }

  @override
  String get weekdayLetters => 'ஞா,தி,செ,பு,வி,வெ,ச';

  @override
  String runsUntil(Object date) {
    return '$date வரை இயங்கும்';
  }
}
