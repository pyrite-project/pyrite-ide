import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/git/git_models.dart';
import 'package:pyrite_ide/core/services/git/git_provider.dart';
import 'package:pyrite_ide/pages/git/git_page.dart';

const _remoteName = 'origin';
const _oldUrl = 'https://example.com/old.git';
const _newUrl = 'https://example.com/new.git';

const _editUrlDialogTitle = '编辑远端 URL';
const _editUrlConfirmTitle = '修改远端 URL';
const _remoteTabLabel = '远端';
const _confirmLabel = '确认';

void main() {
  testWidgets('saving a remote URL keeps the confirmation dialog open', (
    tester,
  ) async {
    final notifier = await _pumpGitPage(tester);
    await _openEditUrlDialog(tester);
    await tester.enterText(_dialogTextField(), _newUrl);

    await tester.tap(_dialogConfirmButton(_editUrlDialogTitle));
    await tester.pumpAndSettle();

    // The confirmation must survive the submit callback that pushed it.
    expect(
      find.widgetWithText(AlertDialog, _editUrlConfirmTitle),
      findsOneWidget,
    );
    expect(notifier.remoteUrlUpdates, isEmpty);

    await tester.tap(_dialogConfirmButton(_editUrlConfirmTitle));
    await tester.pumpAndSettle();

    expect(notifier.remoteUrlUpdates, [(name: _remoteName, url: _newUrl)]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('pressing Enter keeps the remote confirmation dialog open', (
    tester,
  ) async {
    final notifier = await _pumpGitPage(tester);
    await _openEditUrlDialog(tester);
    await tester.enterText(_dialogTextField(), _newUrl);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(AlertDialog, _editUrlConfirmTitle),
      findsOneWidget,
    );
    expect(notifier.remoteUrlUpdates, isEmpty);

    await tester.tap(_dialogConfirmButton(_editUrlConfirmTitle));
    await tester.pumpAndSettle();

    expect(notifier.remoteUrlUpdates, [(name: _remoteName, url: _newUrl)]);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'submitting again while the confirmation is pending runs it once',
    (tester) async {
      final notifier = await _pumpGitPage(tester);
      await _openEditUrlDialog(tester);
      await tester.enterText(_dialogTextField(), _newUrl);

      // Activate the same submit twice before the first one can finish. The
      // first call is suspended on its confirmation dialog, so the second must
      // be ignored rather than stacking another operation.
      final field = tester.widget<TextField>(_dialogTextField());
      field.onSubmitted!(_newUrl);
      field.onSubmitted!(_newUrl);
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(AlertDialog, _editUrlConfirmTitle),
        findsOneWidget,
        reason: 'the second submit must not stack a second confirmation',
      );
      expect(
        tester
            .widget<FilledButton>(_dialogConfirmButton(_editUrlDialogTitle))
            .onPressed,
        isNull,
        reason: 'the action must be disabled while it is in flight',
      );

      await tester.tap(_dialogConfirmButton(_editUrlConfirmTitle));
      await tester.pumpAndSettle();

      expect(notifier.remoteUrlUpdates, [(name: _remoteName, url: _newUrl)]);
    },
  );
}

Future<_RecordingGitNotifier> _pumpGitPage(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [gitProvider.overrideWith(_RecordingGitNotifier.new)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GitPage()),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(
    find.descendant(
      of: find.byType(TabBar),
      matching: find.text(_remoteTabLabel),
    ),
  );
  await tester.pumpAndSettle();

  return container.read(gitProvider.notifier) as _RecordingGitNotifier;
}

Future<void> _openEditUrlDialog(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

Finder _dialogTextField() {
  return find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );
}

Finder _dialogConfirmButton(String dialogTitle) {
  return find.descendant(
    of: find.widgetWithText(AlertDialog, dialogTitle),
    matching: find.widgetWithText(FilledButton, _confirmLabel),
  );
}

class _RecordingGitNotifier extends GitNotifier {
  _RecordingGitNotifier(super.ref) {
    state = const GitViewState(
      workspacePath: '/repo',
      snapshot: GitRepositorySnapshot(
        rootPath: '/repo',
        gitDir: '/repo/.git',
        branchLabel: 'main',
        stateLabel: 'Clean',
        isDetached: false,
        isEmpty: false,
        authorName: 'Test User',
        authorEmail: 'test@example.com',
        ahead: 0,
        behind: 0,
        statusEntries: [],
        branches: [],
        remotes: [
          GitRemoteInfo(
            name: _remoteName,
            url: _oldUrl,
            pushUrl: _oldUrl,
            fetchRefspecs: ['+refs/heads/*:refs/remotes/origin/*'],
            pushRefspecs: [],
          ),
        ],
        stashes: [],
        tags: [],
        submodules: [],
        worktrees: [],
        commits: [],
        conflicts: [],
        stagedPatch: '',
        unstagedPatch: '',
      ),
    );
  }

  final List<({String name, String url})> remoteUrlUpdates = [];

  @override
  Future<void> refresh({String? workspacePath}) async {}

  @override
  Future<void> setRemoteUrl(String name, String url) async {
    remoteUrlUpdates.add((name: name, url: url));
  }
}
