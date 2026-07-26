// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Telugu (`te`).
class L10nTe extends L10n {
  L10nTe([String locale = 'te']) : super(locale);

  @override
  String get appName => 'My Train';

  @override
  String get navTrack => 'ట్రాక్';

  @override
  String get navPnr => 'PNR';

  @override
  String get navBook => 'బుకింగ్';

  @override
  String get navProfile => 'ప్రొఫైల్';

  @override
  String get heroTitle => 'మీ తదుపరి ప్రయాణాన్ని ట్రాక్ చేయండి';

  @override
  String get heroSubtitle =>
      'భారతదేశం అంతటా లైవ్ స్టేటస్, PNR మరియు ప్లాట్‌ఫారమ్ సమాచారం';

  @override
  String get nearestStation => 'సమీప స్టేషన్';

  @override
  String get usingNearestStation => 'సమీప స్టేషన్ ఉపయోగించబడుతోంది';

  @override
  String get searchByRoute => 'మార్గం ద్వారా';

  @override
  String get searchByTrainNo => 'రైలు నంబర్ ద్వారా';

  @override
  String get fieldFrom => 'ఎక్కడ నుండి';

  @override
  String get fieldTo => 'ఎక్కడికి';

  @override
  String get selectStation => 'స్టేషన్ ఎంచుకోండి';

  @override
  String get searchTrains => 'రైళ్లను వెతకండి';

  @override
  String get hintTrainNumber => 'రైలు నంబర్ నమోదు చేయండి (ఉదా. 12951)';

  @override
  String get hintSearchAny => 'రైలు పేరు, నంబర్ లేదా స్టేషన్ వెతకండి';

  @override
  String get searchCityStationCode => 'నగరం, స్టేషన్ లేదా కోడ్ వెతకండి';

  @override
  String get selectOrigin => 'బయలుదేరే స్టేషన్ ఎంచుకోండి';

  @override
  String get selectDestination => 'గమ్య స్టేషన్ ఎంచుకోండి';

  @override
  String get sectionRecent => 'ఇటీవలివి';

  @override
  String get sectionPopular => 'ప్రసిద్ధ స్టేషన్లు';

  @override
  String get filterAllTrains => 'అన్ని రైళ్లు';

  @override
  String get filterNearby => 'సమీపంలో';

  @override
  String get filterRunningStatus => 'రన్నింగ్ స్టేటస్';

  @override
  String get filterPnrStatus => 'PNR స్టేటస్';

  @override
  String get filterLiveMap => 'లైవ్ మ్యాప్';

  @override
  String get filterExpress => 'ఎక్స్‌ప్రెస్';

  @override
  String get filterSuperfast => 'సూపర్‌ఫాస్ట్';

  @override
  String get filterPassenger => 'పాసింజర్';

  @override
  String get filterOnTime => 'సమయానికి';

  @override
  String get filterDelayed => 'ఆలస్యం';

  @override
  String countDepartures(int count) {
    return '$count రాబోయే బయలుదేరడాలు';
  }

  @override
  String countNearYou(int count) {
    return 'మీ దగ్గర $count రైళ్లు';
  }

  @override
  String countRunning(int count) {
    return '$count రైళ్లు నడుస్తున్నాయి';
  }

  @override
  String countOnRoute(int count, Object from, Object to) {
    return '$count రైళ్లు · $from → $to';
  }

  @override
  String countMatching(int count, Object query) {
    return '\"$query\" కి సరిపోలే $count';
  }

  @override
  String get noTrainsMatch => 'మీ ఫిల్టర్‌లకు సరిపోలే రైళ్లు లేవు';

  @override
  String get statusOnTime => 'సమయానికి';

  @override
  String statusDelayedMin(int minutes) {
    return '$minutes నిమిషాలు ఆలస్యం';
  }

  @override
  String platformAndEta(Object platform, int minutes) {
    return 'PF $platform · $minutes నిమిషాల్లో';
  }

  @override
  String get platformTba => 'ప్లాట్‌ఫారమ్ ప్రకటించలేదు';

  @override
  String get liveGps => 'లైవ్ GPS';

  @override
  String get pantry => 'పాంట్రీ';

  @override
  String get acThreeTier => 'AC 3-టైర్';

  @override
  String get acTwoTier => 'AC 2-టైర్';

  @override
  String scheduledDays(Object days) {
    return 'షెడ్యూల్ · $days';
  }

  @override
  String get runsDaily => 'ప్రతిరోజూ';

  @override
  String get bookTitle => 'మీ టికెట్ బుక్ చేయండి';

  @override
  String get bookBody => 'రిజర్వేషన్ అధికారిక IRCTC పోర్టల్‌లో జరుగుతుంది.';

  @override
  String get bookCta => 'IRCTC కి కొనసాగించండి';

  @override
  String get bookSheetTitle => 'IRCTC లో బుక్ చేయండి';

  @override
  String get bookSheetBody =>
      'టికెట్ బుకింగ్ అధికారిక IRCTC పోర్టల్‌లో జరుగుతుంది.';

  @override
  String get bookOpening => 'IRCTC తెరుస్తోంది — అనుసంధానం త్వరలో';

  @override
  String get cancel => 'రద్దు చేయి';

  @override
  String get tryAgain => 'మళ్లీ ప్రయత్నించండి';

  @override
  String get gotIt => 'అర్థమైంది';

  @override
  String get pnrHint => '10 అంకెల PNR';

  @override
  String get pnrCheckCta => 'PNR స్టేటస్ చూడండి';

  @override
  String get pnrNotFoundTitle => 'PNR కనబడలేదు';

  @override
  String pnrNotFoundBody(Object pnr) {
    return 'PNR $pnr కనుగొనలేకపోయాము. మీ టికెట్‌పై ఉన్న 10 అంకెల నంబర్ సరిచూసి మళ్లీ ప్రయత్నించండి.';
  }

  @override
  String get pnrSampleTip =>
      'సూచన: లైవ్ ఉదాహరణ చూడటానికి పైన ఉన్న నమూనాను నొక్కండి.';

  @override
  String get pnrSampleConfirmed => 'కన్ఫర్మ్';

  @override
  String get pnrSampleWaitlisted => 'వెయిటింగ్ లిస్ట్';

  @override
  String get pnrSampleMixed => 'మిశ్రమం';

  @override
  String get checkBackLaterTitle => 'తర్వాత చూడండి';

  @override
  String get pnrQuotaBody =>
      'నెలవారీ అభ్యర్థన పరిమితి చేరుకోవడంతో లైవ్ PNR సమాచారం తాత్కాలికంగా అందుబాటులో లేదు. తర్వాత ప్రయత్నించండి.';

  @override
  String get routeUnavailableTitle => 'మార్గం అందుబాటులో లేదు';

  @override
  String routeUnavailableGeneric(Object number) {
    return 'రైలు $number మార్గాన్ని లోడ్ చేయలేకపోయాము.';
  }

  @override
  String get routeUnavailableNotConnected =>
      'ఈ బిల్డ్‌లో లైవ్ మార్గ డేటా ఇంకా అనుసంధానించబడలేదు.';

  @override
  String get routeUnavailableQuota =>
      'లైవ్ రైల్వే డేటా తాత్కాలికంగా అందుబాటులో లేదు. తర్వాత చూడండి.';

  @override
  String routeUnavailableInconsistent(Object number) {
    return 'రైలు $number మార్గ డేటా అస్థిరంగా కనిపిస్తోంది, కాబట్టి చూపడం లేదు.';
  }

  @override
  String liveTimelineStations(int count) {
    return 'లైవ్ టైమ్‌లైన్ · $count స్టేషన్లు';
  }

  @override
  String get destinationAlarm => 'గమ్యస్థాన అలారం';

  @override
  String get coachPosition => 'కోచ్ స్థానం';

  @override
  String get setAlarm => 'అలారం సెట్ చేయి';

  @override
  String get unableToFetchRoute =>
      'మార్గాన్ని పొందలేకపోయాము. కనెక్షన్ సరిచూడండి.';

  @override
  String get settingsTitle => 'సెట్టింగ్‌లు';

  @override
  String get sectionAppearance => 'రూపం';

  @override
  String get themeSystem => 'సిస్టమ్';

  @override
  String get themeLight => 'లైట్';

  @override
  String get themeDark => 'డార్క్';

  @override
  String get appearanceHint =>
      'My Train ఎలా కనిపించాలో ఎంచుకోండి. \"సిస్టమ్\" మీ పరికర సెట్టింగ్‌ను అనుసరిస్తుంది.';

  @override
  String get sectionLanguage => 'భాష';

  @override
  String get language => 'భాష';

  @override
  String get sectionAbout => 'యాప్ గురించి';

  @override
  String aboutVersion(Object version) {
    return 'వెర్షన్ $version';
  }

  @override
  String get aboutCoverage => 'కవరేజ్';

  @override
  String aboutCoverageValue(Object count) {
    return '$count రైల్వే స్టేషన్లు';
  }

  @override
  String get aboutStationData => 'స్టేషన్ డేటా';

  @override
  String get chooseLanguage => 'భాష ఎంచుకోండి';

  @override
  String get chooseLanguageSubtitle =>
      'My Train ను ఏ భాషలో చదవాలనుకుంటున్నారో ఎంచుకోండి.';

  @override
  String get submit => 'సమర్పించు';

  @override
  String languageChanged(Object language) {
    return 'భాష $language కి సెట్ చేయబడింది';
  }

  @override
  String platformNumber(Object platform) {
    return 'ప్లాట్‌ఫారమ్ $platform';
  }

  @override
  String get weekdayLetters => 'ఆది,సోమ,మంగ,బుధ,గురు,శుక్ర,శని';

  @override
  String runsUntil(Object date) {
    return '$date వరకు నడుస్తుంది';
  }
}
