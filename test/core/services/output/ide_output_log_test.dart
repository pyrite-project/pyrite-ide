import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/output/ide_output_log.dart';

class _LogDuringBuild extends ConsumerStatefulWidget {
  const _LogDuringBuild();

  @override
  ConsumerState<_LogDuringBuild> createState() => _LogDuringBuildState();
}

class _LogDuringBuildState extends ConsumerState<_LogDuringBuild> {
  bool _logged = false;

  @override
  Widget build(BuildContext context) {
    if (!_logged) {
      _logged = true;
      final log = ref.read(ideOutputLogProvider.notifier);
      log.add(IdeOutputSource.plugin, 'first');
      log.add(IdeOutputSource.plugin, 'second');
    }
    return Text('${ref.watch(ideOutputLogProvider).length}');
  }
}

void main() {
  test('plugin output retains plugin and session scope', () {
    final notifier = IdeOutputLogNotifier();
    addTearDown(notifier.dispose);

    notifier.add(
      IdeOutputSource.plugin,
      'scoped',
      pluginId: 'fixture',
      sessionId: 'session-1',
    );

    expect(notifier.state.single.pluginId, 'fixture');
    expect(notifier.state.single.sessionId, 'session-1');
  });

  testWidgets('defers provider updates requested while the tree is building', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _LogDuringBuild()),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(container.read(ideOutputLogProvider), hasLength(2));
    expect(find.text('2'), findsOneWidget);
  });
}
