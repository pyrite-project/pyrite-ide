enum GitCredentialMode { none, httpsToken, sshAgent, sshKey }

enum GitConflictSide { ours, theirs }

class GitCredentialDraft {
  const GitCredentialDraft({
    this.mode = GitCredentialMode.none,
    this.username = '',
    this.token = '',
    this.publicKeyPath = '',
    this.privateKeyPath = '',
    this.passphrase = '',
  });

  final GitCredentialMode mode;
  final String username;
  final String token;
  final String publicKeyPath;
  final String privateKeyPath;
  final String passphrase;

  GitCredentialDraft copyWith({
    GitCredentialMode? mode,
    String? username,
    String? token,
    String? publicKeyPath,
    String? privateKeyPath,
    String? passphrase,
  }) {
    return GitCredentialDraft(
      mode: mode ?? this.mode,
      username: username ?? this.username,
      token: token ?? this.token,
      publicKeyPath: publicKeyPath ?? this.publicKeyPath,
      privateKeyPath: privateKeyPath ?? this.privateKeyPath,
      passphrase: passphrase ?? this.passphrase,
    );
  }
}

class GitRepositorySnapshot {
  const GitRepositorySnapshot({
    required this.rootPath,
    required this.gitDir,
    required this.branchLabel,
    required this.stateLabel,
    required this.isDetached,
    required this.isEmpty,
    required this.authorName,
    required this.authorEmail,
    required this.ahead,
    required this.behind,
    required this.statusEntries,
    required this.branches,
    required this.remotes,
    required this.stashes,
    required this.tags,
    required this.submodules,
    required this.worktrees,
    required this.commits,
    required this.conflicts,
    required this.stagedPatch,
    required this.unstagedPatch,
  });

  final String rootPath;
  final String gitDir;
  final String branchLabel;
  final String stateLabel;
  final bool isDetached;
  final bool isEmpty;
  final String authorName;
  final String authorEmail;
  final int ahead;
  final int behind;
  final List<GitStatusEntry> statusEntries;
  final List<GitBranchInfo> branches;
  final List<GitRemoteInfo> remotes;
  final List<GitStashInfo> stashes;
  final List<GitTagInfo> tags;
  final List<GitSubmoduleInfo> submodules;
  final List<GitWorktreeInfo> worktrees;
  final List<GitCommitInfo> commits;
  final List<GitConflictInfo> conflicts;
  final String stagedPatch;
  final String unstagedPatch;

  bool get hasRepository => rootPath.isNotEmpty;
  bool get hasChanges => statusEntries.isNotEmpty;
  bool get hasConflicts => conflicts.isNotEmpty;
  int get stagedCount => statusEntries.where((entry) => entry.isStaged).length;
  int get unstagedCount {
    return statusEntries.where((entry) => entry.isUnstaged).length;
  }
}

class GitStatusEntry {
  const GitStatusEntry({
    required this.path,
    required this.labels,
    required this.isStaged,
    required this.isUnstaged,
    required this.isConflicted,
    required this.isUntracked,
  });

  final String path;
  final List<String> labels;
  final bool isStaged;
  final bool isUnstaged;
  final bool isConflicted;
  final bool isUntracked;

  String get summary => labels.join(' / ');
}

class GitBranchInfo {
  const GitBranchInfo({
    required this.name,
    required this.targetSha,
    required this.isCurrent,
    required this.isRemote,
    required this.upstream,
  });

  final String name;
  final String targetSha;
  final bool isCurrent;
  final bool isRemote;
  final String upstream;
}

class GitRemoteInfo {
  const GitRemoteInfo({
    required this.name,
    required this.url,
    required this.pushUrl,
    required this.fetchRefspecs,
    required this.pushRefspecs,
  });

  final String name;
  final String url;
  final String pushUrl;
  final List<String> fetchRefspecs;
  final List<String> pushRefspecs;
}

class GitCommitInfo {
  const GitCommitInfo({
    required this.sha,
    required this.shortSha,
    required this.summary,
    required this.author,
    required this.email,
    required this.time,
    required this.parentShas,
  });

  final String sha;
  final String shortSha;
  final String summary;
  final String author;
  final String email;
  final DateTime time;
  final List<String> parentShas;
}

class GitStashInfo {
  const GitStashInfo({
    required this.index,
    required this.sha,
    required this.message,
  });

  final int index;
  final String sha;
  final String message;
}

class GitTagInfo {
  const GitTagInfo({required this.name, required this.targetSha});

  final String name;
  final String targetSha;
}

class GitSubmoduleInfo {
  const GitSubmoduleInfo({
    required this.name,
    required this.path,
    required this.url,
    required this.branch,
    required this.statusLabels,
  });

  final String name;
  final String path;
  final String url;
  final String branch;
  final List<String> statusLabels;
}

class GitWorktreeInfo {
  const GitWorktreeInfo({
    required this.name,
    required this.path,
    required this.isLocked,
    required this.isPrunable,
    required this.isValid,
  });

  final String name;
  final String path;
  final bool isLocked;
  final bool isPrunable;
  final bool isValid;
}

class GitConflictInfo {
  const GitConflictInfo({
    required this.path,
    required this.ancestorPath,
    required this.oursPath,
    required this.theirsPath,
    required this.basePreview,
    required this.oursPreview,
    required this.theirsPreview,
    required this.mergedPreview,
  });

  final String path;
  final String ancestorPath;
  final String oursPath;
  final String theirsPath;
  final String basePreview;
  final String oursPreview;
  final String theirsPreview;
  final String mergedPreview;
}

class GitBlameLine {
  const GitBlameLine({
    required this.lineStart,
    required this.lineCount,
    required this.commitSha,
    required this.author,
    required this.email,
    required this.time,
  });

  final int lineStart;
  final int lineCount;
  final String commitSha;
  final String author;
  final String email;
  final DateTime? time;
}

class GitViewState {
  const GitViewState({
    this.snapshot,
    this.workspacePath,
    this.credentials = const GitCredentialDraft(),
    this.selectedPath,
    this.selectedStaged = false,
    this.selectedPatch = '',
    this.blame = const [],
    this.isBusy = false,
    this.error,
    this.lastMessage,
  });

  final GitRepositorySnapshot? snapshot;
  final String? workspacePath;
  final GitCredentialDraft credentials;
  final String? selectedPath;
  final bool selectedStaged;
  final String selectedPatch;
  final List<GitBlameLine> blame;
  final bool isBusy;
  final String? error;
  final String? lastMessage;

  GitViewState copyWith({
    GitRepositorySnapshot? snapshot,
    String? workspacePath,
    GitCredentialDraft? credentials,
    String? selectedPath,
    bool? selectedStaged,
    String? selectedPatch,
    List<GitBlameLine>? blame,
    bool? isBusy,
    String? error,
    String? lastMessage,
    bool clearError = false,
    bool clearLastMessage = false,
    bool clearSnapshot = false,
    bool clearSelection = false,
  }) {
    return GitViewState(
      snapshot: clearSnapshot ? null : snapshot ?? this.snapshot,
      workspacePath: workspacePath ?? this.workspacePath,
      credentials: credentials ?? this.credentials,
      selectedPath: clearSelection ? null : selectedPath ?? this.selectedPath,
      selectedStaged: clearSelection
          ? false
          : selectedStaged ?? this.selectedStaged,
      selectedPatch: clearSelection ? '' : selectedPatch ?? this.selectedPatch,
      blame: clearSelection ? const [] : blame ?? this.blame,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : error ?? this.error,
      lastMessage: clearLastMessage ? null : lastMessage ?? this.lastMessage,
    );
  }
}
