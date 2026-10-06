/// The editor context-menu entries that depend on an LSP capability switch.
///
/// Kept separate from the widget so the mapping from a setting to the entries
/// it controls can be read — and tested — without building an editor.
enum EditorLspMenuAction {
  goToDefinition,
  goToImplementation,
  rename,
  findReferences,
}

/// Works out which LSP-backed entries the context menu should offer.
///
/// [hasLanguageServer] is false when the file was opened without a server,
/// which is the case for every non-Python file until "对所有文件启用" is turned
/// on. Without a server there is nothing for any of these entries to ask, so
/// none of them are offered.
///
/// [goToDefinition] and [rename] come from the capability switches rather than
/// from the server's initialization snapshot: the menu is assembled during
/// build, so reading them live is what makes an entry appear or disappear on
/// the file the user is already looking at.
///
/// "Go to implementation" shares the definition switch. Both go through the
/// same jump, and `textDocument/implementation` has no capability of its own —
/// a server that answers nothing simply leaves the jump without a target.
Set<EditorLspMenuAction> lspContextMenuActions({
  required bool hasLanguageServer,
  required bool goToDefinition,
  required bool rename,
}) {
  if (!hasLanguageServer) return const {};
  return {
    if (goToDefinition) ...[
      EditorLspMenuAction.goToDefinition,
      EditorLspMenuAction.goToImplementation,
    ],
    if (rename) EditorLspMenuAction.rename,
    EditorLspMenuAction.findReferences,
  };
}
