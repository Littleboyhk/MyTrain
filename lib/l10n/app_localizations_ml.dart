// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Malayalam (`ml`).
class L10nMl extends L10n {
  L10nMl([String locale = 'ml']) : super(locale);

  @override
  String get appName => 'My Train';

  @override
  String get navTrack => 'ട്രാക്ക്';

  @override
  String get navPnr => 'PNR';

  @override
  String get navBook => 'ബുക്കിംഗ്';

  @override
  String get navProfile => 'പ്രൊഫൈൽ';

  @override
  String get heroTitle => 'നിങ്ങളുടെ അടുത്ത യാത്ര ട്രാക്ക് ചെയ്യുക';

  @override
  String get heroSubtitle =>
      'ഇന്ത്യയിലെമ്പാടും ലൈവ് സ്റ്റാറ്റസ്, PNR, പ്ലാറ്റ്ഫോം വിവരങ്ങൾ';

  @override
  String get nearestStation => 'അടുത്തുള്ള സ്റ്റേഷൻ';

  @override
  String get usingNearestStation => 'അടുത്തുള്ള സ്റ്റേഷൻ ഉപയോഗിക്കുന്നു';

  @override
  String get searchByRoute => 'റൂട്ട് പ്രകാരം';

  @override
  String get searchByTrainNo => 'ട്രെയിൻ നമ്പർ പ്രകാരം';

  @override
  String get fieldFrom => 'എവിടെ നിന്ന്';

  @override
  String get fieldTo => 'എവിടേക്ക്';

  @override
  String get selectStation => 'സ്റ്റേഷൻ തിരഞ്ഞെടുക്കുക';

  @override
  String get searchTrains => 'ട്രെയിനുകൾ തിരയുക';

  @override
  String get hintTrainNumber => 'ട്രെയിൻ നമ്പർ നൽകുക (ഉദാ. 12951)';

  @override
  String get hintSearchAny =>
      'ട്രെയിനിന്റെ പേര്, നമ്പർ അല്ലെങ്കിൽ സ്റ്റേഷൻ തിരയുക';

  @override
  String get searchCityStationCode => 'നഗരം, സ്റ്റേഷൻ അല്ലെങ്കിൽ കോഡ് തിരയുക';

  @override
  String get selectOrigin => 'പുറപ്പെടുന്ന സ്റ്റേഷൻ തിരഞ്ഞെടുക്കുക';

  @override
  String get selectDestination => 'ലക്ഷ്യ സ്റ്റേഷൻ തിരഞ്ഞെടുക്കുക';

  @override
  String get sectionRecent => 'സമീപകാലം';

  @override
  String get sectionPopular => 'ജനപ്രിയ സ്റ്റേഷനുകൾ';

  @override
  String get filterAllTrains => 'എല്ലാ ട്രെയിനുകളും';

  @override
  String get filterNearby => 'സമീപത്ത്';

  @override
  String get filterRunningStatus => 'റണ്ണിംഗ് സ്റ്റാറ്റസ്';

  @override
  String get filterPnrStatus => 'PNR സ്റ്റാറ്റസ്';

  @override
  String get filterLiveMap => 'ലൈവ് മാപ്പ്';

  @override
  String get filterExpress => 'എക്സ്പ്രസ്';

  @override
  String get filterSuperfast => 'സൂപ്പർഫാസ്റ്റ്';

  @override
  String get filterPassenger => 'പാസഞ്ചർ';

  @override
  String get filterOnTime => 'സമയത്ത്';

  @override
  String get filterDelayed => 'വൈകി';

  @override
  String countDepartures(int count) {
    return '$count വരാനിരിക്കുന്ന പുറപ്പെടലുകൾ';
  }

  @override
  String countNearYou(int count) {
    return 'നിങ്ങൾക്ക് സമീപം $count ട്രെയിനുകൾ';
  }

  @override
  String countRunning(int count) {
    return '$count ട്രെയിനുകൾ ഓടുന്നു';
  }

  @override
  String countOnRoute(int count, Object from, Object to) {
    return '$count ട്രെയിനുകൾ · $from → $to';
  }

  @override
  String countMatching(int count, Object query) {
    return '\"$query\" എന്നതിനോട് യോജിക്കുന്ന $count';
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
  String get noTrainsMatch =>
      'നിങ്ങളുടെ ഫിൽട്ടറുകൾക്ക് അനുയോജ്യമായ ട്രെയിനുകളില്ല';

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
  String get statusOnTime => 'സമയത്ത്';

  @override
  String statusDelayedMin(int minutes) {
    return '$minutes മിനിറ്റ് വൈകി';
  }

  @override
  String platformAndEta(Object platform, int minutes) {
    return 'PF $platform · $minutes മിനിറ്റിനുള്ളിൽ';
  }

  @override
  String get platformTba => 'പ്ലാറ്റ്ഫോം അറിയിച്ചിട്ടില്ല';

  @override
  String get liveGps => 'ലൈവ് GPS';

  @override
  String get pantry => 'പാൻട്രി';

  @override
  String get acThreeTier => 'AC 3-ടയർ';

  @override
  String get acTwoTier => 'AC 2-ടയർ';

  @override
  String scheduledDays(Object days) {
    return 'ഷെഡ്യൂൾ · $days';
  }

  @override
  String get runsDaily => 'ദിവസവും';

  @override
  String get bookTitle => 'നിങ്ങളുടെ ടിക്കറ്റ് ബുക്ക് ചെയ്യുക';

  @override
  String get bookBody => 'റിസർവേഷൻ ഔദ്യോഗിക IRCTC പോർട്ടലിലാണ് നടക്കുന്നത്.';

  @override
  String get bookCta => 'IRCTC-യിലേക്ക് തുടരുക';

  @override
  String get bookSheetTitle => 'IRCTC-യിൽ ബുക്ക് ചെയ്യുക';

  @override
  String get bookSheetBody =>
      'ടിക്കറ്റ് ബുക്കിംഗ് ഔദ്യോഗിക IRCTC പോർട്ടലിൽ നടക്കുന്നു.';

  @override
  String get bookOpening => 'IRCTC തുറക്കുന്നു — സംയോജനം ഉടൻ വരുന്നു';

  @override
  String get cancel => 'റദ്ദാക്കുക';

  @override
  String get tryAgain => 'വീണ്ടും ശ്രമിക്കുക';

  @override
  String get gotIt => 'മനസ്സിലായി';

  @override
  String get pnrHint => '10 അക്ക PNR';

  @override
  String get pnrCheckCta => 'PNR സ്റ്റാറ്റസ് പരിശോധിക്കുക';

  @override
  String get pnrNotFoundTitle => 'PNR കണ്ടെത്തിയില്ല';

  @override
  String pnrNotFoundBody(Object pnr) {
    return 'PNR $pnr കണ്ടെത്താനായില്ല. നിങ്ങളുടെ ടിക്കറ്റിലെ 10 അക്ക നമ്പർ പരിശോധിച്ച് വീണ്ടും ശ്രമിക്കുക.';
  }

  @override
  String get pnrSampleTip =>
      'സൂചന: ലൈവ് ഉദാഹരണം കാണാൻ മുകളിലുള്ള സാമ്പിളിൽ ടാപ്പ് ചെയ്യുക.';

  @override
  String get pnrSampleConfirmed => 'കൺഫേം';

  @override
  String get pnrSampleWaitlisted => 'വെയിറ്റ്‌ലിസ്റ്റ്';

  @override
  String get pnrSampleMixed => 'മിശ്രിതം';

  @override
  String get checkBackLaterTitle => 'പിന്നീട് പരിശോധിക്കുക';

  @override
  String get pnrQuotaBody =>
      'പ്രതിമാസ അഭ്യർത്ഥന പരിധി എത്തിയതിനാൽ ലൈവ് PNR വിവരങ്ങൾ താൽക്കാലികമായി ലഭ്യമല്ല. പിന്നീട് ശ്രമിക്കുക.';

  @override
  String get routeUnavailableTitle => 'റൂട്ട് ലഭ്യമല്ല';

  @override
  String routeUnavailableGeneric(Object number) {
    return 'ട്രെയിൻ $number-ന്റെ റൂട്ട് ലോഡ് ചെയ്യാനായില്ല.';
  }

  @override
  String get routeUnavailableNotConnected =>
      'ഈ ബിൽഡിൽ ലൈവ് റൂട്ട് ഡാറ്റ ഇനിയും ബന്ധിപ്പിച്ചിട്ടില്ല.';

  @override
  String get routeUnavailableQuota =>
      'ലൈവ് റെയിൽവേ ഡാറ്റ താൽക്കാലികമായി ലഭ്യമല്ല. പിന്നീട് പരിശോധിക്കുക.';

  @override
  String routeUnavailableInconsistent(Object number) {
    return 'ട്രെയിൻ $number-ന്റെ റൂട്ട് ഡാറ്റ പൊരുത്തമില്ലാത്തതായി തോന്നുന്നു, അതിനാൽ കാണിക്കുന്നില്ല.';
  }

  @override
  String liveTimelineStations(int count) {
    return 'ലൈവ് ടൈംലൈൻ · $count സ്റ്റേഷനുകൾ';
  }

  @override
  String get destinationAlarm => 'ലക്ഷ്യസ്ഥാന അലാം';

  @override
  String get coachPosition => 'കോച്ച് സ്ഥാനം';

  @override
  String get setAlarm => 'അലാം സെറ്റ് ചെയ്യുക';

  @override
  String get unableToFetchRoute =>
      'റൂട്ട് ലഭ്യമാക്കാനായില്ല. കണക്ഷൻ പരിശോധിക്കുക.';

  @override
  String get settingsTitle => 'ക്രമീകരണങ്ങൾ';

  @override
  String get sectionAppearance => 'രൂപം';

  @override
  String get themeSystem => 'സിസ്റ്റം';

  @override
  String get themeLight => 'ലൈറ്റ്';

  @override
  String get themeDark => 'ഡാർക്ക്';

  @override
  String get appearanceHint =>
      'My Train എങ്ങനെ കാണണമെന്ന് തിരഞ്ഞെടുക്കുക. \"സിസ്റ്റം\" നിങ്ങളുടെ ഉപകരണ ക്രമീകരണം പിന്തുടരും.';

  @override
  String get sectionLanguage => 'ഭാഷ';

  @override
  String get language => 'ഭാഷ';

  @override
  String get sectionAbout => 'ആപ്പിനെക്കുറിച്ച്';

  @override
  String aboutVersion(Object version) {
    return 'പതിപ്പ് $version';
  }

  @override
  String get aboutCoverage => 'കവറേജ്';

  @override
  String aboutCoverageValue(Object count) {
    return '$count റെയിൽവേ സ്റ്റേഷനുകൾ';
  }

  @override
  String get aboutStationData => 'സ്റ്റേഷൻ ഡാറ്റ';

  @override
  String get chooseLanguage => 'ഭാഷ തിരഞ്ഞെടുക്കുക';

  @override
  String get chooseLanguageSubtitle =>
      'My Train ഏത് ഭാഷയിൽ വായിക്കണമെന്ന് തിരഞ്ഞെടുക്കുക.';

  @override
  String get submit => 'സമർപ്പിക്കുക';

  @override
  String languageChanged(Object language) {
    return 'ഭാഷ $language ആയി സജ്ജമാക്കി';
  }

  @override
  String platformNumber(Object platform) {
    return 'പ്ലാറ്റ്ഫോം $platform';
  }

  @override
  String get weekdayLetters => 'ഞാ,തി,ചൊ,ബു,വ്യാ,വെ,ശ';

  @override
  String runsUntil(Object date) {
    return '$date വരെ ഓടുന്നു';
  }
}
