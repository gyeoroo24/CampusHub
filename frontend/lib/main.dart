import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/ui/session_keeper.dart';

void main() {
  usePathUrlStrategy();
  // context.push('/profile') etc. should show their own URL, so a refresh stays on that page.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  runApp(const ProviderScope(child: CampusHubApp()));
}

class CampusHubApp extends ConsumerWidget {
  const CampusHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: 'CampusHub | IISc',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      themeAnimationDuration: Duration.zero,
      routerConfig: appRouter,
      builder: (context, child) => SessionKeeper(child: child ?? const SizedBox.shrink()),
    );
  }
}
