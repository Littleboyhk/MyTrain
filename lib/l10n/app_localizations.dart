import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_as.dart';
import 'app_localizations_bn.dart';
import 'app_localizations_en.dart';
import 'app_localizations_gu.dart';
import 'app_localizations_hi.dart';
import 'app_localizations_kn.dart';
import 'app_localizations_ml.dart';
import 'app_localizations_mr.dart';
import 'app_localizations_or.dart';
import 'app_localizations_pa.dart';
import 'app_localizations_ta.dart';
import 'app_localizations_te.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L10n
/// returned by `L10n.of(context)`.
///
/// Applications need to include `L10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L10n.localizationsDelegates,
///   supportedLocales: L10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L10n.supportedLocales
/// property.
abstract class L10n {
  L10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L10n of(BuildContext context) {
    return Localizations.of<L10n>(context, L10n)!;
  }

  static const LocalizationsDelegate<L10n> delegate = _L10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('as'),
    Locale('bn'),
    Locale('en'),
    Locale('gu'),
    Locale('hi'),
    Locale('kn'),
    Locale('ml'),
    Locale('mr'),
    Locale('or'),
    Locale('pa'),
    Locale('ta'),
    Locale('te'),
  ];

  /// Brand name — intentionally NOT translated in any locale.
  ///
  /// In en, this message translates to:
  /// **'My Train'**
  String get appName;

  /// No description provided for @navTrack.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get navTrack;

  /// No description provided for @navPnr.
  ///
  /// In en, this message translates to:
  /// **'PNR'**
  String get navPnr;

  /// No description provided for @navBook.
  ///
  /// In en, this message translates to:
  /// **'Book'**
  String get navBook;

  /// No description provided for @navProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get navProfile;

  /// No description provided for @heroTitle.
  ///
  /// In en, this message translates to:
  /// **'Track your next journey'**
  String get heroTitle;

  /// No description provided for @heroSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Live status, PNR & platform info across India'**
  String get heroSubtitle;

  /// No description provided for @nearestStation.
  ///
  /// In en, this message translates to:
  /// **'Nearest Station'**
  String get nearestStation;

  /// No description provided for @usingNearestStation.
  ///
  /// In en, this message translates to:
  /// **'Using nearest station'**
  String get usingNearestStation;

  /// No description provided for @searchByRoute.
  ///
  /// In en, this message translates to:
  /// **'By Route'**
  String get searchByRoute;

  /// No description provided for @searchByTrainNo.
  ///
  /// In en, this message translates to:
  /// **'By Train No.'**
  String get searchByTrainNo;

  /// No description provided for @fieldFrom.
  ///
  /// In en, this message translates to:
  /// **'FROM'**
  String get fieldFrom;

  /// No description provided for @fieldTo.
  ///
  /// In en, this message translates to:
  /// **'TO'**
  String get fieldTo;

  /// No description provided for @selectStation.
  ///
  /// In en, this message translates to:
  /// **'Select station'**
  String get selectStation;

  /// No description provided for @searchTrains.
  ///
  /// In en, this message translates to:
  /// **'Search Trains'**
  String get searchTrains;

  /// No description provided for @hintTrainNumber.
  ///
  /// In en, this message translates to:
  /// **'Enter train number (e.g. 12951)'**
  String get hintTrainNumber;

  /// No description provided for @hintSearchAny.
  ///
  /// In en, this message translates to:
  /// **'Search train name, number or station'**
  String get hintSearchAny;

  /// No description provided for @searchCityStationCode.
  ///
  /// In en, this message translates to:
  /// **'Search city, station or code'**
  String get searchCityStationCode;

  /// No description provided for @selectOrigin.
  ///
  /// In en, this message translates to:
  /// **'Select origin'**
  String get selectOrigin;

  /// No description provided for @selectDestination.
  ///
  /// In en, this message translates to:
  /// **'Select destination'**
  String get selectDestination;

  /// No description provided for @sectionRecent.
  ///
  /// In en, this message translates to:
  /// **'RECENT'**
  String get sectionRecent;

  /// No description provided for @sectionPopular.
  ///
  /// In en, this message translates to:
  /// **'POPULAR STATIONS'**
  String get sectionPopular;

  /// No description provided for @filterAllTrains.
  ///
  /// In en, this message translates to:
  /// **'All Trains'**
  String get filterAllTrains;

  /// No description provided for @filterNearby.
  ///
  /// In en, this message translates to:
  /// **'Nearby'**
  String get filterNearby;

  /// No description provided for @filterRunningStatus.
  ///
  /// In en, this message translates to:
  /// **'Running Status'**
  String get filterRunningStatus;

  /// No description provided for @filterPnrStatus.
  ///
  /// In en, this message translates to:
  /// **'PNR Status'**
  String get filterPnrStatus;

  /// No description provided for @filterLiveMap.
  ///
  /// In en, this message translates to:
  /// **'Live Map'**
  String get filterLiveMap;

  /// No description provided for @filterExpress.
  ///
  /// In en, this message translates to:
  /// **'Express'**
  String get filterExpress;

  /// No description provided for @filterSuperfast.
  ///
  /// In en, this message translates to:
  /// **'Superfast'**
  String get filterSuperfast;

  /// No description provided for @filterPassenger.
  ///
  /// In en, this message translates to:
  /// **'Passenger'**
  String get filterPassenger;

  /// No description provided for @filterOnTime.
  ///
  /// In en, this message translates to:
  /// **'On Time'**
  String get filterOnTime;

  /// No description provided for @filterDelayed.
  ///
  /// In en, this message translates to:
  /// **'Delayed'**
  String get filterDelayed;

  /// No description provided for @countDepartures.
  ///
  /// In en, this message translates to:
  /// **'{count} upcoming departures'**
  String countDepartures(int count);

  /// No description provided for @countNearYou.
  ///
  /// In en, this message translates to:
  /// **'{count} trains near you'**
  String countNearYou(int count);

  /// No description provided for @countRunning.
  ///
  /// In en, this message translates to:
  /// **'{count} trains running'**
  String countRunning(int count);

  /// No description provided for @countOnRoute.
  ///
  /// In en, this message translates to:
  /// **'{count} trains · {from} → {to}'**
  String countOnRoute(int count, Object from, Object to);

  /// No description provided for @countMatching.
  ///
  /// In en, this message translates to:
  /// **'{count} matching \"{query}\"'**
  String countMatching(int count, Object query);

  /// No description provided for @sectionPersonal.
  ///
  /// In en, this message translates to:
  /// **'PERSONAL'**
  String get sectionPersonal;

  /// No description provided for @sectionSpot.
  ///
  /// In en, this message translates to:
  /// **'SPOT SETTINGS'**
  String get sectionSpot;

  /// No description provided for @sectionSpeedometer.
  ///
  /// In en, this message translates to:
  /// **'SPEEDOMETER SETTINGS'**
  String get sectionSpeedometer;

  /// No description provided for @sectionAlarm.
  ///
  /// In en, this message translates to:
  /// **'ALARM SETTINGS'**
  String get sectionAlarm;

  /// No description provided for @timeSettings.
  ///
  /// In en, this message translates to:
  /// **'Time settings'**
  String get timeSettings;

  /// No description provided for @timeSettingsHint.
  ///
  /// In en, this message translates to:
  /// **'Show times as AM/PM instead of 24-hour'**
  String get timeSettingsHint;

  /// No description provided for @insideTrainSetting.
  ///
  /// In en, this message translates to:
  /// **'Are you inside train option'**
  String get insideTrainSetting;

  /// No description provided for @insideTrainSettingHint.
  ///
  /// In en, this message translates to:
  /// **'Suggest sharing your location when a journey opens'**
  String get insideTrainSettingHint;

  /// No description provided for @spotNotifications.
  ///
  /// In en, this message translates to:
  /// **'Spot notifications'**
  String get spotNotifications;

  /// No description provided for @spotNotificationsHint.
  ///
  /// In en, this message translates to:
  /// **'Your location as a standing notification'**
  String get spotNotificationsHint;

  /// Shown instead of the normal hint when a standing notification cannot be delivered on this platform.
  ///
  /// In en, this message translates to:
  /// **'Not available in this build — needs a notification plugin, and has no web equivalent'**
  String get spotNotificationsUnsupported;

  /// No description provided for @speedometerSetting.
  ///
  /// In en, this message translates to:
  /// **'Speedometer (Beta)'**
  String get speedometerSetting;

  /// No description provided for @speedometerSettingHint.
  ///
  /// In en, this message translates to:
  /// **'Show live GPS speed while tracking'**
  String get speedometerSettingHint;

  /// No description provided for @speedometerRequiresGps.
  ///
  /// In en, this message translates to:
  /// **'Appears on the tracking screen once you start sharing your location in GPS mode, which is where the speed reading comes from.'**
  String get speedometerRequiresGps;

  /// No description provided for @alarmTone.
  ///
  /// In en, this message translates to:
  /// **'Alarm tone'**
  String get alarmTone;

  /// No description provided for @alarmToneChanged.
  ///
  /// In en, this message translates to:
  /// **'Alarm tone set to {tone}'**
  String alarmToneChanged(String tone);

  /// No description provided for @alarmTonePlaybackNote.
  ///
  /// In en, this message translates to:
  /// **'Select an alarm tone to preview and set your preferred sound.'**
  String get alarmTonePlaybackNote;

  /// No description provided for @noTrainsMatch.
  ///
  /// In en, this message translates to:
  /// **'No trains match your filters'**
  String get noTrainsMatch;

  /// Shown when a train-number lookup completed successfully but no such train exists.
  ///
  /// In en, this message translates to:
  /// **'Train {number} not found'**
  String trainNotFound(String number);

  /// No description provided for @trainNotFoundHint.
  ///
  /// In en, this message translates to:
  /// **'Check the number and try again'**
  String get trainNotFoundHint;

  /// Shown when a train-number lookup could not be completed at all (offline, quota, server error). Deliberately different from trainNotFound, because the user's next action is to retry rather than to correct the number.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t check right now'**
  String get trainLookupFailed;

  /// No description provided for @trainLookupFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong reaching the railway data. Try again in a moment.'**
  String get trainLookupFailedHint;

  /// No description provided for @searchingTrain.
  ///
  /// In en, this message translates to:
  /// **'Looking up train {number}…'**
  String searchingTrain(String number);

  /// No description provided for @statusOnTime.
  ///
  /// In en, this message translates to:
  /// **'On time'**
  String get statusOnTime;

  /// No description provided for @statusDelayedMin.
  ///
  /// In en, this message translates to:
  /// **'Delayed {minutes}m'**
  String statusDelayedMin(int minutes);

  /// No description provided for @platformAndEta.
  ///
  /// In en, this message translates to:
  /// **'PF {platform} · in {minutes} min'**
  String platformAndEta(Object platform, int minutes);

  /// No description provided for @platformTba.
  ///
  /// In en, this message translates to:
  /// **'Platform TBA'**
  String get platformTba;

  /// No description provided for @liveGps.
  ///
  /// In en, this message translates to:
  /// **'Live GPS'**
  String get liveGps;

  /// No description provided for @pantry.
  ///
  /// In en, this message translates to:
  /// **'Pantry'**
  String get pantry;

  /// No description provided for @acThreeTier.
  ///
  /// In en, this message translates to:
  /// **'AC 3-Tier'**
  String get acThreeTier;

  /// No description provided for @acTwoTier.
  ///
  /// In en, this message translates to:
  /// **'AC 2-Tier'**
  String get acTwoTier;

  /// No description provided for @scheduledDays.
  ///
  /// In en, this message translates to:
  /// **'Scheduled · {days}'**
  String scheduledDays(Object days);

  /// No description provided for @runsDaily.
  ///
  /// In en, this message translates to:
  /// **'Daily'**
  String get runsDaily;

  /// No description provided for @bookTitle.
  ///
  /// In en, this message translates to:
  /// **'Book your tickets'**
  String get bookTitle;

  /// No description provided for @bookBody.
  ///
  /// In en, this message translates to:
  /// **'Reservations are handled on the official IRCTC portal.'**
  String get bookBody;

  /// No description provided for @bookCta.
  ///
  /// In en, this message translates to:
  /// **'Continue to IRCTC'**
  String get bookCta;

  /// No description provided for @bookSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Book on IRCTC'**
  String get bookSheetTitle;

  /// No description provided for @bookSheetBody.
  ///
  /// In en, this message translates to:
  /// **'Ticket booking happens on the official IRCTC portal.'**
  String get bookSheetBody;

  /// No description provided for @bookOpening.
  ///
  /// In en, this message translates to:
  /// **'Opening IRCTC — integration coming soon'**
  String get bookOpening;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @pnrHint.
  ///
  /// In en, this message translates to:
  /// **'10-digit PNR'**
  String get pnrHint;

  /// No description provided for @pnrCheckCta.
  ///
  /// In en, this message translates to:
  /// **'Check PNR Status'**
  String get pnrCheckCta;

  /// No description provided for @pnrNotFoundTitle.
  ///
  /// In en, this message translates to:
  /// **'PNR not found'**
  String get pnrNotFoundTitle;

  /// No description provided for @pnrNotFoundBody.
  ///
  /// In en, this message translates to:
  /// **'We couldn\'t find PNR {pnr}. Double-check the 10-digit number on your ticket and try again.'**
  String pnrNotFoundBody(Object pnr);

  /// No description provided for @pnrSampleTip.
  ///
  /// In en, this message translates to:
  /// **'Tip: tap a sample above to see a live example.'**
  String get pnrSampleTip;

  /// No description provided for @pnrSampleConfirmed.
  ///
  /// In en, this message translates to:
  /// **'Confirmed'**
  String get pnrSampleConfirmed;

  /// No description provided for @pnrSampleWaitlisted.
  ///
  /// In en, this message translates to:
  /// **'Waitlisted'**
  String get pnrSampleWaitlisted;

  /// No description provided for @pnrSampleMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get pnrSampleMixed;

  /// No description provided for @checkBackLaterTitle.
  ///
  /// In en, this message translates to:
  /// **'Check back later'**
  String get checkBackLaterTitle;

  /// No description provided for @pnrQuotaBody.
  ///
  /// In en, this message translates to:
  /// **'Live PNR lookups are temporarily unavailable because the monthly request limit was reached. Please try again later.'**
  String get pnrQuotaBody;

  /// No description provided for @routeUnavailableTitle.
  ///
  /// In en, this message translates to:
  /// **'Route unavailable'**
  String get routeUnavailableTitle;

  /// No description provided for @routeUnavailableGeneric.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the route for train {number}.'**
  String routeUnavailableGeneric(Object number);

  /// No description provided for @routeUnavailableNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Live route data isn\'t connected in this build yet.'**
  String get routeUnavailableNotConnected;

  /// No description provided for @routeUnavailableQuota.
  ///
  /// In en, this message translates to:
  /// **'Live railway data is temporarily unavailable. Please check back later.'**
  String get routeUnavailableQuota;

  /// No description provided for @routeUnavailableInconsistent.
  ///
  /// In en, this message translates to:
  /// **'Route data for train {number} looks inconsistent, so it\'s not being shown.'**
  String routeUnavailableInconsistent(Object number);

  /// No description provided for @liveTimelineStations.
  ///
  /// In en, this message translates to:
  /// **'LIVE TIMELINE · {count} STATIONS'**
  String liveTimelineStations(int count);

  /// No description provided for @destinationAlarm.
  ///
  /// In en, this message translates to:
  /// **'Destination Alarm'**
  String get destinationAlarm;

  /// No description provided for @coachPosition.
  ///
  /// In en, this message translates to:
  /// **'Coach Position'**
  String get coachPosition;

  /// No description provided for @setAlarm.
  ///
  /// In en, this message translates to:
  /// **'Set Alarm'**
  String get setAlarm;

  /// No description provided for @unableToFetchRoute.
  ///
  /// In en, this message translates to:
  /// **'Unable to fetch route. Please check connection.'**
  String get unableToFetchRoute;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @sectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'APPEARANCE'**
  String get sectionAppearance;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @appearanceHint.
  ///
  /// In en, this message translates to:
  /// **'Choose how My Train looks. \"System\" follows your device setting automatically.'**
  String get appearanceHint;

  /// No description provided for @sectionLanguage.
  ///
  /// In en, this message translates to:
  /// **'LANGUAGE'**
  String get sectionLanguage;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @sectionAbout.
  ///
  /// In en, this message translates to:
  /// **'ABOUT'**
  String get sectionAbout;

  /// No description provided for @aboutVersion.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersion(Object version);

  /// No description provided for @aboutCoverage.
  ///
  /// In en, this message translates to:
  /// **'Coverage'**
  String get aboutCoverage;

  /// No description provided for @aboutCoverageValue.
  ///
  /// In en, this message translates to:
  /// **'{count} railway stations'**
  String aboutCoverageValue(Object count);

  /// No description provided for @aboutStationData.
  ///
  /// In en, this message translates to:
  /// **'Station data'**
  String get aboutStationData;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose a language'**
  String get chooseLanguage;

  /// No description provided for @chooseLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Pick how you\'d like to read My Train.'**
  String get chooseLanguageSubtitle;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @languageChanged.
  ///
  /// In en, this message translates to:
  /// **'Language set to {language}'**
  String languageChanged(Object language);

  /// No description provided for @platformNumber.
  ///
  /// In en, this message translates to:
  /// **'Platform {platform}'**
  String platformNumber(Object platform);

  /// Comma-separated weekday abbreviations, SUNDAY FIRST. Must contain exactly 7 items.
  ///
  /// In en, this message translates to:
  /// **'S,M,T,W,Th,F,Sa'**
  String get weekdayLetters;

  /// No description provided for @runsUntil.
  ///
  /// In en, this message translates to:
  /// **'Runs till {date}'**
  String runsUntil(Object date);
}

class _L10nDelegate extends LocalizationsDelegate<L10n> {
  const _L10nDelegate();

  @override
  Future<L10n> load(Locale locale) {
    return SynchronousFuture<L10n>(lookupL10n(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'as',
    'bn',
    'en',
    'gu',
    'hi',
    'kn',
    'ml',
    'mr',
    'or',
    'pa',
    'ta',
    'te',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_L10nDelegate old) => false;
}

L10n lookupL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'as':
      return L10nAs();
    case 'bn':
      return L10nBn();
    case 'en':
      return L10nEn();
    case 'gu':
      return L10nGu();
    case 'hi':
      return L10nHi();
    case 'kn':
      return L10nKn();
    case 'ml':
      return L10nMl();
    case 'mr':
      return L10nMr();
    case 'or':
      return L10nOr();
    case 'pa':
      return L10nPa();
    case 'ta':
      return L10nTa();
    case 'te':
      return L10nTe();
  }

  throw FlutterError(
    'L10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
