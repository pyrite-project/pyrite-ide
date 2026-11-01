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
    this.ahead = 0,
    this.behind = 0,
    this.hasUpstream = false,
  });

  final String name;
  final String targetSha;
  final bool isCurrent;
  final bool isRemote;
  final String upstream;

  /// 相对 upstream 领先/落后多少个提交。
  ///
  /// 远端分支没有本地 upstream 概念，因此始终为 0；本地分支如果从未配置
  /// upstream（[hasUpstream] 为 false）同样保持 0，UI 不应把 0 误读成“同步”。
  final int ahead;
  final int behind;

  /// 是否已配置 upstream（[upstream] 非空且可解析）。
  final bool hasUpstream;

  /// `origin/main` 形式的 upstream 展示文本，无 upstream 时返回空串。
  String get upstreamLabel => upstream;

  /// `↑1 ↓2` 形式的跟踪摘要，无 upstream 时返回空串。
  String get trackingLabel {
    if (!hasUpstream) return '';
    return '↑$ahead ↓$behind';
  }
}

class GitCheckoutBlocked {
  const GitCheckoutBlocked({
    required this.branchName,
    required this.remote,
    required this.paths,
    required this.message,
  });

  final String branchName;
  final bool remote;
  final List<String> paths;
  final String message;
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
  const GitTagInfo({
    required this.name,
    required this.targetSha,
    this.isAnnotated = false,
    this.message = '',
  });

  final String name;
  final String targetSha;

  /// 是否为 annotated tag（带 tagger/message 的 tag 对象）。
  ///
  /// 仅用于 UI 区分展示；[targetSha] 保留 ref 指向的原始对象 SHA，与
  /// annotated tag 自身的对象 SHA 不是同一个值。
  final bool isAnnotated;

  /// annotated tag 的消息首行，lightweight tag 为空串。
  final String message;
}

/// 创建 tag 的参数。
///
/// [message] 非空时创建 annotated tag；为空时保持既有的 lightweight 路径，
/// 避免改变现有“Tag HEAD”按钮的语义。
class GitTagInput {
  const GitTagInput({
    required this.name,
    this.message = '',
    this.targetSpec = 'HEAD',
    this.force = false,
  });

  final String name;
  final String message;
  final String targetSpec;
  final bool force;

  bool get isAnnotated => message.trim().isNotEmpty;
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

  /// 7 位短 SHA，用于 gutter 等空间紧张的展示位。
  String get shortSha =>
      commitSha.length <= 7 ? commitSha : commitSha.substring(0, 7);

  /// 该 hunk 覆盖的行区间（含首尾，1 基）。
  int get lineEnd => lineStart + lineCount - 1;

  GitBlameLine copyWith({
    int? lineStart,
    int? lineCount,
    String? commitSha,
    String? author,
    String? email,
    DateTime? time,
  }) {
    return GitBlameLine(
      lineStart: lineStart ?? this.lineStart,
      lineCount: lineCount ?? this.lineCount,
      commitSha: commitSha ?? this.commitSha,
      author: author ?? this.author,
      email: email ?? this.email,
      time: time ?? this.time,
    );
  }
}

/// 把 blame hunk 展开成“每一行对应一个注释”的列表。
///
/// libgit2 的 blame 以连续行为单位（hunk）返回，UI 需要按行渲染；这里在
/// 服务层完成展开，避免页面重复实现同一段映射逻辑。行号从 1 开始，缺失的
/// 行号用空 author 补齐（例如 diff 预览里的空行）。
List<GitBlameLine> expandGitBlameLines(
  List<GitBlameLine> hunks, {
  int? lineCount,
}) {
  if (hunks.isEmpty) return const [];
  final byLine = <int, GitBlameLine>{};
  for (final hunk in hunks) {
    if (hunk.lineCount <= 0) continue;
    for (var offset = 0; offset < hunk.lineCount; offset += 1) {
      byLine[hunk.lineStart + offset] = hunk.copyWith(
        lineStart: hunk.lineStart + offset,
        lineCount: 1,
      );
    }
  }
  final maxLine =
      lineCount ?? byLine.keys.fold<int>(0, (a, b) => a > b ? a : b);
  return [
    for (var line = 1; line <= maxLine; line += 1)
      if (byLine[line] != null)
        byLine[line]!
      else
        GitBlameLine(
          lineStart: line,
          lineCount: 1,
          commitSha: '',
          author: '',
          email: '',
          time: null,
        ),
  ];
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
    this.blamePath,
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

  /// 当前 blame 对应的文件路径（[blame] 非空时才有意义）。
  final String? blamePath;

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
    String? blamePath,
    bool? isBusy,
    String? error,
    String? lastMessage,
    bool clearError = false,
    bool clearLastMessage = false,
    bool clearSnapshot = false,
    bool clearSelection = false,
    bool clearBlamePath = false,
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
      blamePath: clearSelection || clearBlamePath
          ? null
          : blamePath ?? this.blamePath,
      isBusy: isBusy ?? this.isBusy,
      error: clearError ? null : error ?? this.error,
      lastMessage: clearLastMessage ? null : lastMessage ?? this.lastMessage,
    );
  }
}
