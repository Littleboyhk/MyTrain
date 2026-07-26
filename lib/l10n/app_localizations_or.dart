// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Oriya (`or`).
class L10nOr extends L10n {
  L10nOr([String locale = 'or']) : super(locale);

  @override
  String get appName => 'My Train';

  @override
  String get navTrack => 'ଟ୍ରାକ୍';

  @override
  String get navPnr => 'PNR';

  @override
  String get navBook => 'ବୁକିଂ';

  @override
  String get navProfile => 'ପ୍ରୋଫାଇଲ୍';

  @override
  String get heroTitle => 'ଆପଣଙ୍କ ପରବର୍ତ୍ତୀ ଯାତ୍ରା ଟ୍ରାକ୍ କରନ୍ତୁ';

  @override
  String get heroSubtitle => 'ସମଗ୍ର ଭାରତରେ ଲାଇଭ୍ ସ୍ଥିତି, PNR ଓ ପ୍ଲାଟଫର୍ମ ସୂଚନା';

  @override
  String get nearestStation => 'ନିକଟତମ ଷ୍ଟେଶନ';

  @override
  String get usingNearestStation => 'ନିକଟତମ ଷ୍ଟେଶନ ବ୍ୟବହାର ହେଉଛି';

  @override
  String get searchByRoute => 'ମାର୍ଗ ଅନୁଯାୟୀ';

  @override
  String get searchByTrainNo => 'ଟ୍ରେନ୍ ନମ୍ବର ଅନୁଯାୟୀ';

  @override
  String get fieldFrom => 'କେଉଁଠାରୁ';

  @override
  String get fieldTo => 'କେଉଁଠାକୁ';

  @override
  String get selectStation => 'ଷ୍ଟେଶନ ବାଛନ୍ତୁ';

  @override
  String get searchTrains => 'ଟ୍ରେନ୍ ଖୋଜନ୍ତୁ';

  @override
  String get hintTrainNumber => 'ଟ୍ରେନ୍ ନମ୍ବର ଦିଅନ୍ତୁ (ଯଥା 12951)';

  @override
  String get hintSearchAny => 'ଟ୍ରେନ୍ ନାମ, ନମ୍ବର କିମ୍ବା ଷ୍ଟେଶନ ଖୋଜନ୍ତୁ';

  @override
  String get searchCityStationCode => 'ସହର, ଷ୍ଟେଶନ କିମ୍ବା କୋଡ୍ ଖୋଜନ୍ତୁ';

  @override
  String get selectOrigin => 'ପ୍ରସ୍ଥାନ ଷ୍ଟେଶନ ବାଛନ୍ତୁ';

  @override
  String get selectDestination => 'ଗନ୍ତବ୍ୟ ଷ୍ଟେଶନ ବାଛନ୍ତୁ';

  @override
  String get sectionRecent => 'ସାମ୍ପ୍ରତିକ';

  @override
  String get sectionPopular => 'ଲୋକପ୍ରିୟ ଷ୍ଟେଶନ';

  @override
  String get filterAllTrains => 'ସମସ୍ତ ଟ୍ରେନ୍';

  @override
  String get filterNearby => 'ନିକଟରେ';

  @override
  String get filterRunningStatus => 'ଚଳାଚଳ ସ୍ଥିତି';

  @override
  String get filterPnrStatus => 'PNR ସ୍ଥିତି';

  @override
  String get filterLiveMap => 'ଲାଇଭ୍ ମ୍ୟାପ୍';

  @override
  String get filterExpress => 'ଏକ୍ସପ୍ରେସ୍';

  @override
  String get filterSuperfast => 'ସୁପରଫାସ୍ଟ';

  @override
  String get filterPassenger => 'ପାସେଞ୍ଜର୍';

  @override
  String get filterOnTime => 'ସମୟରେ';

  @override
  String get filterDelayed => 'ବିଳମ୍ବ';

  @override
  String countDepartures(int count) {
    return '$count ଆଗାମୀ ପ୍ରସ୍ଥାନ';
  }

  @override
  String countNearYou(int count) {
    return 'ଆପଣଙ୍କ ନିକଟରେ $count ଟ୍ରେନ୍';
  }

  @override
  String countRunning(int count) {
    return '$count ଟ୍ରେନ୍ ଚାଲୁଛି';
  }

  @override
  String countOnRoute(int count, Object from, Object to) {
    return '$count ଟ୍ରେନ୍ · $from → $to';
  }

  @override
  String countMatching(int count, Object query) {
    return '\"$query\" ସହ ମେଳ ହେଉଥିବା $count';
  }

  @override
  String get noTrainsMatch => 'ଆପଣଙ୍କ ଫିଲ୍ଟର ସହ କୌଣସି ଟ୍ରେନ୍ ମେଳ ହେଉନାହିଁ';

  @override
  String get statusOnTime => 'ସମୟରେ';

  @override
  String statusDelayedMin(int minutes) {
    return '$minutes ମିନିଟ୍ ବିଳମ୍ବ';
  }

  @override
  String platformAndEta(Object platform, int minutes) {
    return 'PF $platform · $minutes ମିନିଟ୍‌ରେ';
  }

  @override
  String get platformTba => 'ପ୍ଲାଟଫର୍ମ ଘୋଷଣା ହୋଇନାହିଁ';

  @override
  String get liveGps => 'ଲାଇଭ୍ GPS';

  @override
  String get pantry => 'ପାନ୍ଟ୍ରି';

  @override
  String get acThreeTier => 'AC 3-ଟାୟାର';

  @override
  String get acTwoTier => 'AC 2-ଟାୟାର';

  @override
  String scheduledDays(Object days) {
    return 'ନିର୍ଧାରିତ · $days';
  }

  @override
  String get runsDaily => 'ପ୍ରତିଦିନ';

  @override
  String get bookTitle => 'ଆପଣଙ୍କ ଟିକଟ ବୁକ୍ କରନ୍ତୁ';

  @override
  String get bookBody => 'ସଂରକ୍ଷଣ ସରକାରୀ IRCTC ପୋର୍ଟାଲରେ ହୁଏ।';

  @override
  String get bookCta => 'IRCTC କୁ ଆଗେଇ ଯାଆନ୍ତୁ';

  @override
  String get bookSheetTitle => 'IRCTC ରେ ବୁକ୍ କରନ୍ତୁ';

  @override
  String get bookSheetBody => 'ଟିକଟ ବୁକିଂ ସରକାରୀ IRCTC ପୋର୍ଟାଲରେ ହୁଏ।';

  @override
  String get bookOpening => 'IRCTC ଖୋଲୁଛି — ସଂଯୋଗ ଶୀଘ୍ର ଆସୁଛି';

  @override
  String get cancel => 'ବାତିଲ୍ କରନ୍ତୁ';

  @override
  String get tryAgain => 'ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ';

  @override
  String get gotIt => 'ବୁଝିଲି';

  @override
  String get pnrHint => '10 ଅଙ୍କର PNR';

  @override
  String get pnrCheckCta => 'PNR ସ୍ଥିତି ଦେଖନ୍ତୁ';

  @override
  String get pnrNotFoundTitle => 'PNR ମିଳିଲା ନାହିଁ';

  @override
  String pnrNotFoundBody(Object pnr) {
    return 'PNR $pnr ମିଳିଲା ନାହିଁ। ଆପଣଙ୍କ ଟିକଟରେ ଥିବା 10 ଅଙ୍କର ନମ୍ବର ଯାଞ୍ଚ କରି ପୁଣି ଚେଷ୍ଟା କରନ୍ତୁ।';
  }

  @override
  String get pnrSampleTip =>
      'ପରାମର୍ଶ: ଲାଇଭ୍ ଉଦାହରଣ ଦେଖିବାକୁ ଉପରର ନମୁନାରେ ଟ୍ୟାପ୍ କରନ୍ତୁ।';

  @override
  String get pnrSampleConfirmed => 'ନିଶ୍ଚିତ';

  @override
  String get pnrSampleWaitlisted => 'ଅପେକ୍ଷା ତାଲିକା';

  @override
  String get pnrSampleMixed => 'ମିଶ୍ରିତ';

  @override
  String get checkBackLaterTitle => 'ପରେ ଦେଖନ୍ତୁ';

  @override
  String get pnrQuotaBody =>
      'ମାସିକ ଅନୁରୋଧ ସୀମା ପୂରଣ ହେବାରୁ ଲାଇଭ୍ PNR ସୂଚନା ଅସ୍ଥାୟୀ ଭାବେ ଉପଲବ୍ଧ ନାହିଁ। ପରେ ଚେଷ୍ଟା କରନ୍ତୁ।';

  @override
  String get routeUnavailableTitle => 'ମାର୍ଗ ଉପଲବ୍ଧ ନାହିଁ';

  @override
  String routeUnavailableGeneric(Object number) {
    return 'ଟ୍ରେନ୍ $number ର ମାର୍ଗ ଲୋଡ୍ ହୋଇପାରିଲା ନାହିଁ।';
  }

  @override
  String get routeUnavailableNotConnected =>
      'ଏହି ବିଲ୍ଡରେ ଲାଇଭ୍ ମାର୍ଗ ଡାଟା ଏପର୍ଯ୍ୟନ୍ତ ସଂଯୁକ୍ତ ନାହିଁ।';

  @override
  String get routeUnavailableQuota =>
      'ଲାଇଭ୍ ରେଳବାଇ ଡାଟା ଅସ୍ଥାୟୀ ଭାବେ ଉପଲବ୍ଧ ନାହିଁ। ପରେ ଦେଖନ୍ତୁ।';

  @override
  String routeUnavailableInconsistent(Object number) {
    return 'ଟ୍ରେନ୍ $number ର ମାର୍ଗ ଡାଟା ଅସଙ୍ଗତ ଲାଗୁଛି, ତେଣୁ ଦେଖାଯାଉନାହିଁ।';
  }

  @override
  String liveTimelineStations(int count) {
    return 'ଲାଇଭ୍ ଟାଇମ୍‌ଲାଇନ୍ · $count ଷ୍ଟେଶନ';
  }

  @override
  String get destinationAlarm => 'ଗନ୍ତବ୍ୟ ଆଲାର୍ମ';

  @override
  String get coachPosition => 'କୋଚ୍ ସ୍ଥାନ';

  @override
  String get setAlarm => 'ଆଲାର୍ମ ସେଟ୍ କରନ୍ତୁ';

  @override
  String get unableToFetchRoute => 'ମାର୍ଗ ଆଣିହେଲା ନାହିଁ। ସଂଯୋଗ ଯାଞ୍ଚ କରନ୍ତୁ।';

  @override
  String get settingsTitle => 'ସେଟିଂସ୍';

  @override
  String get sectionAppearance => 'ରୂପ';

  @override
  String get themeSystem => 'ସିଷ୍ଟମ୍';

  @override
  String get themeLight => 'ଲାଇଟ୍';

  @override
  String get themeDark => 'ଡାର୍କ';

  @override
  String get appearanceHint =>
      'My Train କେମିତି ଦେଖାଯିବ ବାଛନ୍ତୁ। \"ସିଷ୍ଟମ୍\" ଆପଣଙ୍କ ଡିଭାଇସର ସେଟିଂ ଅନୁସରଣ କରେ।';

  @override
  String get sectionLanguage => 'ଭାଷା';

  @override
  String get language => 'ଭାଷା';

  @override
  String get sectionAbout => 'ଆପ୍ ବିଷୟରେ';

  @override
  String aboutVersion(Object version) {
    return 'ସଂସ୍କରଣ $version';
  }

  @override
  String get aboutCoverage => 'କଭରେଜ୍';

  @override
  String aboutCoverageValue(Object count) {
    return '$count ରେଳ ଷ୍ଟେଶନ';
  }

  @override
  String get aboutStationData => 'ଷ୍ଟେଶନ ଡାଟା';

  @override
  String get chooseLanguage => 'ଭାଷା ବାଛନ୍ତୁ';

  @override
  String get chooseLanguageSubtitle =>
      'My Train କେଉଁ ଭାଷାରେ ପଢ଼ିବାକୁ ଚାହାଁନ୍ତି ବାଛନ୍ତୁ।';

  @override
  String get submit => 'ଦାଖଲ କରନ୍ତୁ';

  @override
  String languageChanged(Object language) {
    return 'ଭାଷା $language କୁ ସେଟ୍ ହେଲା';
  }

  @override
  String platformNumber(Object platform) {
    return 'ପ୍ଲାଟଫର୍ମ $platform';
  }

  @override
  String get weekdayLetters => 'ରବି,ସୋମ,ମଙ୍ଗ,ବୁଧ,ଗୁରୁ,ଶୁକ୍ର,ଶନି';

  @override
  String runsUntil(Object date) {
    return '$date ପର୍ଯ୍ୟନ୍ତ ଚାଲେ';
  }
}
