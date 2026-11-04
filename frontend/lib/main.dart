import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/cognito_hosted_ui.dart';
import 'features/auth/ui/session_keeper.dart';

void main() {
  // Before the router runs: it rewrites `/?code=...` (the Cognito redirect) to `/buy`.
  CognitoHostedUi.launchUri = Uri.base;
  usePathUrlStrategy();
  // context.push('/profile') etc. should show their own URL, so a refresh stays on that page.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  runApp(const ProviderScope(child: CampusHubApp()));
}

class CampusHubApp extends ConsumerWidget {
  const CampusHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeModeInitProvider); // applies the saved light/dark choice once, on start
    final themeMode = ref.watch(themeModeProvider);
    ref.listen(themeModeProvider, (prev, next) {
      if (prev != next) ThemeModeStorage.save(next);
    });

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
