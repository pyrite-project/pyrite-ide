import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pyrite_ide/core/services/editor/lsp_state.dart';
import 'package:pyrite_ide/core/services/editor/tabbed_view_controller_provider.dart';
import 'package:pyrite_ide/features/function_page/console_tabs.dart';
import 'package:tabbed_view/tabbed_view.dart' hide TabbedView;

void main() {
  test('a tab that is not a document reports no LSP state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(tabbedViewControllerProvider);
    final consoleTab = TabData(
      text: 'REPL',
      value: const ConsoleTabValue(ConsoleTabId.repl),
    );
    controller.addTab(consoleTab);
    controller.selectTab(consoleTab);

    // The console strip and the editor strip exchange tabs, so the selected tab
    // is not always a document: reading `type` off it used to throw.
    expect(container.read(lspState), isNull);
  });
}
