import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'config/supabase_config.dart';
import 'data/app_settings_controller.dart';
import 'data/language_controller.dart';
import 'data/station_coords.dart';
import 'data/theme_controller.dart';
import 'l10n/app_localizations.dart';
import 'screens/home_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'theme/glass_quality.dart';
import 'widgets/app_text_defaults.dart';
import 'widgets/aurora_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Watch frame timings from the very first frame. GlassSurface and
  // AuroraBackground each call this too, but starting here means the launch
  // frames — the ones most likely to be slow on a mid-range device — are counted
  // rather than missed.
  GlassQuality.instance.ensureMonitoring();

  // Load .env environment variables safely
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('[dotenv] .env file not found or failed to load: $e');
  }

  // Pre-warm 8,697 station coordinates in background for instant map rendering
  StationCoords.tryLoad();

  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      // ignore: deprecated_member_use
      anonKey: SupabaseConfig.anonKey,
    );
  }

  // Load prefs up-front so language (and future settings) read synchronously.
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (e) {
    debugPrint('[prefs] SharedPreferences unavailable: $e');
  }

  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const MyTrainApp(),
    ),
  );
}

class MyTrainApp extends ConsumerWidget {
  const MyTrainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    // Selecting a language in the picker rebuilds the whole app in that locale.
    final language = ref.watch(languageProvider);
    // The chosen typeface flows into both themes below. Watching only this
    // field keeps unrelated settings changes from rebuilding the whole app.
    final fontFamily =
        ref.watch(appSettingsProvider.select((s) => s.appFont)).googleFamily;

    // Resolve the effective brightness (mode + platform for "system").
    final platformBrightness =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    final effective = switch (mode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system => platformBrightness,
    };
    final palette =
        effective == Brightness.dark ? AppPalette.dark : AppPalette.light;

    // Point the color tokens at the active palette *before* the tree builds.
    AppColors.palette = palette;

    // Match the system status/navigation bars to the theme.
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            palette.isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: palette.isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: palette.background,
        systemNavigationBarIconBrightness:
            palette.isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return MaterialApp(
      title: 'My Train',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeFor(AppPalette.light, fontFamily: fontFamily),
      darkTheme: AppTheme.themeFor(AppPalette.dark, fontFamily: fontFamily),
      themeMode: mode,
      // Localization: the user's saved choice drives the locale. Keys missing
      // from a translated .arb fall back to English automatically.
      locale: language.locale,
      supportedLocales: L10n.supportedLocales,
      localizationsDelegates: const [
        L10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const HomeScreen(),
      builder: (context, child) {
        // Global animated aurora sits behind every route (scaffolds are
        // transparent), giving the glass surfaces colour to refract.
        // NOTE: do NOT wrap `child` in an AnimatedSwitcher/KeyedSubtree here.
        // `child` contains the app's Navigator (a GlobalObjectKey), so a
        // cross-fade briefly mounts two copies and Flutter throws
        // "Duplicate GlobalKey detected in widget tree", truncating the tree
        // (which showed up as a blank screen). AnimatedTheme already animates
        // theme/brightness changes smoothly without remounting the Navigator.
        return AnimatedTheme(
          data: Theme.of(context),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AuroraBackground(
            // Replaces MaterialApp's ugly fallback DefaultTextStyle, whose
            // yellow double underline leaked into every Cupertino popup and
            // overlay toast in the app. See AppTextDefaults.
            child: AppTextDefaults(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}


