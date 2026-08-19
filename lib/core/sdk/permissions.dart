abstract class Permissions {
  static const Set<String> publicCommands = {
    'sdk.output.append',
    'sdk.path.request',
    // Subscribing is always allowed to reach the bus; the bus enforces the
    // per-topic permission and rejects unauthorized topics itself.
    'sdk.events.subscribe',
    'sdk.events.unsubscribe',
    // Platform and layout mode carry no user data; a plugin needs them to lay
    // itself out correctly, so gating them would only break mobile support.
    'sdk.env.get',
    // A plugin manages the model of its own views; no extra permission needed.
    'sdk.view.open',
    'sdk.view.snapshot',
    'sdk.view.patch',
    'sdk.view.close',
    'sdk.view.focus',
    // Route stacks are per view instance and private to the plugin's own view,
    // so navigating one needs no more trust than drawing it.
    'sdk.view.route.push',
    'sdk.view.route.pop',
    'sdk.view.route.replace',
    'sdk.view.route.goto',
    'sdk.view.component.invoke',
    // Manifest configuration is scoped to the calling plugin's declared ids.
    'sdk.configuration.get',
    'sdk.configuration.set',
    'sdk.configuration.list',
  };

  static const Map<String, String> commandRequirements = {
    // file
    'sdk.file.get_dir_list': 'file:read',
    'sdk.file.get_root_dir': 'file:read',
    'sdk.file.read_file': 'file:read',
    'sdk.file.exists': 'file:read',
    'sdk.file.is_file': 'file:read',
    'sdk.file.is_directory': 'file:read',
    'sdk.file.get_focus_file_node': 'file:read',
    'sdk.file.get_focus_folder_node': 'file:read',
    'sdk.file.get_unique_name': 'file:read',
    'sdk.file.write_file': 'file:write',
    'sdk.file.create_file': 'file:write',
    'sdk.file.create_folder': 'file:write',
    'sdk.file.delete': 'file:write',
    'sdk.file.rename': 'file:write',
    'sdk.file.copy_file': 'file:write',
    'sdk.file.move_file': 'file:write',
    'sdk.file.save_current_file': 'file:write',
    'sdk.file.save_current_file_as': 'file:write',
    'sdk.file.open_file': 'file:read',
    'sdk.file.open_folder': 'file:read',
    'sdk.file.upload_file': 'file:read',
    'sdk.file.upload_selected_local_file_item': 'file:read',

    // board
    'sdk.board.get_dir_list': 'board:read',
    'sdk.board.get_root_dir': 'board:read',
    'sdk.board.read_file': 'board:read',
    'sdk.board.exists': 'board:read',
    'sdk.board.is_file': 'board:read',
    'sdk.board.is_directory': 'board:read',
    'sdk.board.get_focus_file_node': 'board:read',
    'sdk.board.get_focus_folder_node': 'board:read',
    'sdk.board.get_corresponding_file_path': 'board:read',
    'sdk.board.open_file': 'board:read',
    'sdk.board.write_file': 'board:write',
    'sdk.board.delete_file': 'board:write',
    'sdk.board.delete_folder': 'board:write',
    'sdk.board.rename': 'board:write',
    'sdk.board.download_file': 'board:read',
    'sdk.board.download_selected_board_item': 'board:read',

    // editor
    'sdk.editor.get_text': 'editor:read',
    'sdk.editor.get_line_count': 'editor:read',
    'sdk.editor.get_line_text': 'editor:read',
    'sdk.editor.get_selected_text': 'editor:read',
    'sdk.editor.get_cursor_position': 'editor:read',
    'sdk.editor.get_selection': 'editor:read',
    'sdk.editor.can_undo': 'editor:read',
    'sdk.editor.can_redo': 'editor:read',
    'sdk.editor.find': 'editor:read',
    'sdk.editor.find_regex': 'editor:read',
    'sdk.editor.clear_search': 'editor:read',
    'sdk.editor.copy': 'editor:read',
    'sdk.editor.set_text': 'editor:write',
    'sdk.editor.insert_text': 'editor:write',
    'sdk.editor.replace_range': 'editor:write',
    'sdk.editor.clear': 'editor:write',
    'sdk.editor.set_cursor_position': 'editor:write',
    'sdk.editor.set_selection': 'editor:write',
    'sdk.editor.select_all': 'editor:write',
    'sdk.editor.go_to_line': 'editor:write',
    'sdk.editor.undo': 'editor:write',
    'sdk.editor.redo': 'editor:write',
    'sdk.editor.open_file': 'editor:write',
    'sdk.editor.set_ghost_text': 'editor:write',
    'sdk.editor.clear_ghost_text': 'editor:write',
    'sdk.editor.scroll_to_line': 'editor:write',
    'sdk.editor.cut': 'editor:write',
    'sdk.editor.paste': 'editor:write',

    // editor document service (T13)
    'sdk.editor.active_document.get': 'editor:read',
    'sdk.editor.document.get': 'editor:read',
    'sdk.editor.document.symbols': 'editor:read',
    'sdk.editor.document.selection.get': 'editor:read',
    'sdk.editor.document.reveal': 'editor:write',

    // runtime inspection (T14)
    'sdk.runtime.sessions': 'runtime:inspect',
    'sdk.runtime.state': 'runtime:inspect',
    'sdk.runtime.scopes': 'runtime:inspect',
    'sdk.runtime.variables': 'runtime:inspect',
    'sdk.runtime.children': 'runtime:inspect',
    'sdk.runtime.object_info': 'runtime:inspect',

    // persistence
    'sdk.persistence.get': 'persistence:read',
    'sdk.persistence.list_groups': 'persistence:read',
    'sdk.persistence.list_keys': 'persistence:read',
    'sdk.persistence.set': 'persistence:write',
    'sdk.persistence.delete': 'persistence:write',
    'sdk.persistence.clear': 'persistence:write',

    // tab
    'sdk.tab.create_view': 'tab:create',
    'sdk.tab.close': 'tab:manage',
    'sdk.tab.list': 'tab:manage',
    'sdk.tab.activate': 'tab:manage',

    // settings
    'sdk.settings.get': 'settings:read',
    'sdk.settings.set': 'settings:write',
    'sdk.settings.list': 'settings:read',

    // serial (future)
    'sdk.serial.list_ports': 'serial:read',
    'sdk.serial.get_status': 'serial:read',
    'sdk.serial.read': 'serial:read',
    'sdk.serial.connect': 'serial:write',
    'sdk.serial.disconnect': 'serial:write',
    'sdk.serial.send': 'serial:write',
    'sdk.serial.send_command': 'serial:write',
    'sdk.serial.run_python': 'serial:write',
    'sdk.serial.hardware_reset': 'serial:write',
    'sdk.serial.set_baud_rate': 'serial:write',
    'sdk.serial.set_auto_reconnect': 'serial:write',

    // data (theme + i18n)
    'sdk.theme.contribute': 'data:write',
    'sdk.theme.register_runtime': 'data:write',
    'sdk.theme.get': 'data:read',
    'sdk.theme.list': 'data:read',
    'sdk.i18n.contribute': 'data:write',
    'sdk.i18n.register_runtime': 'data:write',
    'sdk.i18n.get': 'data:read',
    'sdk.i18n.list': 'data:read',
    'sdk.stubs.contribute': 'data:write',
    'sdk.stubs.register_runtime': 'data:write',
    'sdk.stubs.revoke': 'data:write',
    'sdk.stubs.get': 'data:read',
    'sdk.stubs.list': 'data:read',
    'sdk.stubs.resolve_layers': 'data:read',
    'sdk.theme.revoke': 'data:write',
    'sdk.i18n.revoke': 'data:write',

    // dialog
    'sdk.dialog.open_folder': 'dialog:show',
    'sdk.dialog.open_file': 'dialog:show',
    'sdk.dialog.open_files': 'dialog:show',

    // message
    'sdk.message.show': 'ui:notify',

    // clipboard
    'sdk.clipboard.set_text': 'ui:view',
  };

  static bool check(
    Map<String, List<String>> pluginPermissions,
    String required,
  ) {
    final colonIndex = required.indexOf(':');
    if (colonIndex == -1) return false;

    final resource = required.substring(0, colonIndex);
    final action = required.substring(colonIndex + 1);

    final allowed = pluginPermissions[resource];
    if (allowed == null) return false;

    if (allowed.contains('*') || allowed.contains(action)) return true;

    if (action == 'read') {
      if (allowed.contains('write')) return true;
    }

    return false;
  }

  static String? getRequirement(String commandType) {
    return commandRequirements[commandType];
  }

  static bool isPublic(String commandType) =>
      publicCommands.contains(commandType);

  static bool isKnown(String commandType) =>
      isPublic(commandType) || commandRequirements.containsKey(commandType);
}
