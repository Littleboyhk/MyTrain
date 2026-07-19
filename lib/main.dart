import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config/supabase_config.dart';
import 'data/theme_controller.dart';
import 'screens/home_screen.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Only connect when configured (see SupabaseConfig). Otherwise the app runs
  // on local mock data so it still works offline / without a backend.
  if (SupabaseConfig.isConfigured) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      // ignore: deprecated_member_use
      anonKey: SupabaseConfig.anonKey,
    );
  }

  runApp(const ProviderScope(child: MyTrainApp()));
}

class MyTrainApp extends ConsumerWidget {
  const MyTrainApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

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
      theme: AppTheme.themeFor(AppPalette.light),
      darkTheme: AppTheme.themeFor(AppPalette.dark),
      themeMode: mode,
      home: const HomeScreen(),
    );
  }
}
