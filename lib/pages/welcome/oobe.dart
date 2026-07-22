import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pyrite_ide/core/services/app.dart';
import 'package:pyrite_ide/core/services/persistence/app_persistence.dart';
import 'package:responsive_framework/responsive_framework.dart';

class WelcomeOobePage extends ConsumerWidget {
  const WelcomeOobePage({super.key});

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    ref.read(welcomeCompletedProvider.notifier).state = true;
    await AppPersistence().save(
      AppPersistedData(
        themeMode: ref.read(themeMode).name,
        themeStyle: ref.read(themeStyle).value,
        themeColorValue: ref.read(themeColor)?.toARGB32(),
        editorThemeKey: ref.read(editorThemeKey),
        activePluginThemeId: ref.read(activePluginThemeId),
        welcomeCompleted: true,
      ),
    );
    if (!context.mounted) return;

    final target = ResponsiveBreakpoints.of(context).isDesktop
        ? '/file'
        : '/editor';
    context.go(target);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/icons/app_icon.webp',
                    width: 80,
                    height: 80,
                  ),
                  SizedBox(height: 20),
                  Text(
                    '欢迎使用 PyriteIDE',
                    style: textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  SizedBox(height: 20),
                  FloatingActionButton(
                    onPressed: () => _complete(context, ref),
                    child: const Icon(Icons.arrow_right_alt_rounded),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
