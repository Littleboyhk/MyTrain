// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Gujarati (`gu`).
class L10nGu extends L10n {
  L10nGu([String locale = 'gu']) : super(locale);

  @override
  String get appName => 'My Train';

  @override
  String get navTrack => 'ટ્રૅક';

  @override
  String get navPnr => 'PNR';

  @override
  String get navBook => 'બુકિંગ';

  @override
  String get navProfile => 'પ્રોફાઇલ';

  @override
  String get heroTitle => 'તમારી આગામી સફર ટ્રૅક કરો';

  @override
  String get heroSubtitle =>
      'સમગ્ર ભારતમાં લાઇવ સ્થિતિ, PNR અને પ્લેટફોર્મ માહિતી';

  @override
  String get nearestStation => 'નજીકનું સ્ટેશન';

  @override
  String get usingNearestStation => 'નજીકનું સ્ટેશન વપરાઈ રહ્યું છે';

  @override
  String get searchByRoute => 'માર્ગ પ્રમાણે';

  @override
  String get searchByTrainNo => 'ટ્રેન નંબર પ્રમાણે';

  @override
  String get fieldFrom => 'ક્યાંથી';

  @override
  String get fieldTo => 'ક્યાં સુધી';

  @override
  String get selectStation => 'સ્ટેશન પસંદ કરો';

  @override
  String get searchTrains => 'ટ્રેનો શોધો';

  @override
  String get hintTrainNumber => 'ટ્રેન નંબર દાખલ કરો (દા.ત. 12951)';

  @override
  String get hintSearchAny => 'ટ્રેનનું નામ, નંબર અથવા સ્ટેશન શોધો';

  @override
  String get searchCityStationCode => 'શહેર, સ્ટેશન અથવા કોડ શોધો';

  @override
  String get selectOrigin => 'પ્રસ્થાન સ્ટેશન પસંદ કરો';

  @override
  String get selectDestination => 'ગંતવ્ય સ્ટેશન પસંદ કરો';

  @override
  String get sectionRecent => 'તાજેતરના';

  @override
  String get sectionPopular => 'લોકપ્રિય સ્ટેશનો';

  @override
  String get filterAllTrains => 'બધી ટ્રેનો';

  @override
  String get filterNearby => 'નજીકમાં';

  @override
  String get filterRunningStatus => 'ચાલવાની સ્થિતિ';

  @override
  String get filterPnrStatus => 'PNR સ્થિતિ';

  @override
  String get filterLiveMap => 'લાઇવ નકશો';

  @override
  String get filterExpress => 'એક્સપ્રેસ';

  @override
  String get filterSuperfast => 'સુપરફાસ્ટ';

  @override
  String get filterPassenger => 'પેસેન્જર';

  @override
  String get filterOnTime => 'સમયસર';

  @override
  String get filterDelayed => 'વિલંબ';

  @override
  String countDepartures(int count) {
    return '$count આગામી પ્રસ્થાનો';
  }

  @override
  String countNearYou(int count) {
    return 'તમારી નજીક $count ટ્રેનો';
  }

  @override
  String countRunning(int count) {
    return '$count ટ્રેનો ચાલી રહી છે';
  }

  @override
  String countOnRoute(int count, Object from, Object to) {
    return '$count ટ્રેનો · $from → $to';
  }

  @override
  String countMatching(int count, Object query) {
    return '\"$query\" સાથે મેળ ખાતી $count';
  }

  @override
  String get noTrainsMatch => 'તમારા ફિલ્ટર સાથે કોઈ ટ્રેન મેળ ખાતી નથી';

  @override
  String get statusOnTime => 'સમયસર';

  @override
  String statusDelayedMin(int minutes) {
    return '$minutes મિનિટ વિલંબ';
  }

  @override
  String platformAndEta(Object platform, int minutes) {
    return 'PF $platform · $minutes મિનિટમાં';
  }

  @override
  String get platformTba => 'પ્લેટફોર્મ જાહેર નથી';

  @override
  String get liveGps => 'લાઇવ GPS';

  @override
  String get pantry => 'પેન્ટ્રી';

  @override
  String get acThreeTier => 'AC 3-ટાયર';

  @override
  String get acTwoTier => 'AC 2-ટાયર';

  @override
  String scheduledDays(Object days) {
    return 'નિર્ધારિત · $days';
  }

  @override
  String get runsDaily => 'દરરોજ';

  @override
  String get bookTitle => 'તમારી ટિકિટ બુક કરો';

  @override
  String get bookBody => 'આરક્ષણ સત્તાવાર IRCTC પોર્ટલ પર થાય છે.';

  @override
  String get bookCta => 'IRCTC પર આગળ વધો';

  @override
  String get bookSheetTitle => 'IRCTC પર બુક કરો';

  @override
  String get bookSheetBody => 'ટિકિટ બુકિંગ સત્તાવાર IRCTC પોર્ટલ પર થાય છે.';

  @override
  String get bookOpening => 'IRCTC ખૂલી રહ્યું છે — સંકલન ટૂંક સમયમાં';

  @override
  String get cancel => 'રદ કરો';

  @override
  String get tryAgain => 'ફરી પ્રયાસ કરો';

  @override
  String get gotIt => 'સમજ્યું';

  @override
  String get pnrHint => '10 અંકનો PNR';

  @override
  String get pnrCheckCta => 'PNR સ્થિતિ તપાસો';

  @override
  String get pnrNotFoundTitle => 'PNR મળ્યો નથી';

  @override
  String pnrNotFoundBody(Object pnr) {
    return 'PNR $pnr મળ્યો નથી. તમારી ટિકિટ પરનો 10 અંકનો નંબર તપાસો અને ફરી પ્રયાસ કરો.';
  }

  @override
  String get pnrSampleTip =>
      'સૂચન: લાઇવ ઉદાહરણ જોવા માટે ઉપરના નમૂના પર ટૅપ કરો.';

  @override
  String get pnrSampleConfirmed => 'કન્ફર્મ';

  @override
  String get pnrSampleWaitlisted => 'વેઇટિંગ લિસ્ટ';

  @override
  String get pnrSampleMixed => 'મિશ્ર';

  @override
  String get checkBackLaterTitle => 'પછી તપાસો';

  @override
  String get pnrQuotaBody =>
      'માસિક વિનંતી મર્યાદા પૂરી થવાથી લાઇવ PNR માહિતી હાલ ઉપલબ્ધ નથી. કૃપા કરીને પછી પ્રયાસ કરો.';

  @override
  String get routeUnavailableTitle => 'માર્ગ ઉપલબ્ધ નથી';

  @override
  String routeUnavailableGeneric(Object number) {
    return 'ટ્રેન $number નો માર્ગ લોડ થઈ શક્યો નથી.';
  }

  @override
  String get routeUnavailableNotConnected =>
      'આ બિલ્ડમાં લાઇવ માર્ગ ડેટા હજી જોડાયેલ નથી.';

  @override
  String get routeUnavailableQuota =>
      'લાઇવ રેલવે ડેટા હાલ ઉપલબ્ધ નથી. કૃપા કરીને પછી તપાસો.';

  @override
  String routeUnavailableInconsistent(Object number) {
    return 'ટ્રેન $number નો માર્ગ ડેટા અસંગત લાગે છે, તેથી બતાવવામાં આવતો નથી.';
  }

  @override
  String liveTimelineStations(int count) {
    return 'લાઇવ ટાઇમલાઇન · $count સ્ટેશનો';
  }

  @override
  String get destinationAlarm => 'ગંતવ્ય એલાર્મ';

  @override
  String get coachPosition => 'કોચ સ્થાન';

  @override
  String get setAlarm => 'એલાર્મ સેટ કરો';

  @override
  String get unableToFetchRoute => 'માર્ગ મેળવી શકાયો નથી. કનેક્શન તપાસો.';

  @override
  String get settingsTitle => 'સેટિંગ્સ';

  @override
  String get sectionAppearance => 'દેખાવ';

  @override
  String get themeSystem => 'સિસ્ટમ';

  @override
  String get themeLight => 'લાઇટ';

  @override
  String get themeDark => 'ડાર્ક';

  @override
  String get appearanceHint =>
      'My Train કેવું દેખાય તે પસંદ કરો. \"સિસ્ટમ\" તમારા ઉપકરણની સેટિંગ અનુસરે છે.';

  @override
  String get sectionLanguage => 'ભાષા';

  @override
  String get language => 'ભાષા';

  @override
  String get sectionAbout => 'એપ્લિકેશન વિશે';

  @override
  String aboutVersion(Object version) {
    return 'આવૃત્તિ $version';
  }

  @override
  String get aboutCoverage => 'કવરેજ';

  @override
  String aboutCoverageValue(Object count) {
    return '$count રેલવે સ્ટેશનો';
  }

  @override
  String get aboutStationData => 'સ્ટેશન ડેટા';

  @override
  String get chooseLanguage => 'ભાષા પસંદ કરો';

  @override
  String get chooseLanguageSubtitle =>
      'My Train કઈ ભાષામાં વાંચવું છે તે પસંદ કરો.';

  @override
  String get submit => 'સબમિટ કરો';

  @override
  String languageChanged(Object language) {
    return 'ભાષા $language પર સેટ કરી';
  }

  @override
  String platformNumber(Object platform) {
    return 'પ્લેટફોર્મ $platform';
  }

  @override
  String get weekdayLetters => 'રવિ,સોમ,મંગળ,બુધ,ગુરુ,શુક્ર,શનિ';

  @override
  String runsUntil(Object date) {
    return '$date સુધી ચાલે છે';
  }
}
