import 'runtime.dart' show FlPiLlm, LlmSession;

/// A message in pi's shape (`AgentMessage`), as JSON.
///
/// Kept as a map rather than a Dart class: pi adds fields to it between
/// releases. Read it through the getters here.
extension type const LlmMessage(Map<String, Object?> json) {
  /// `user`, `assistant`, `toolResult`, `compactionSummary`, ...
  String get role => json['role'] as String? ?? '';

  /// The text parts joined, for display.
  String get text {
    final c = json['content'];
    if (c is String) return c;
    if (c is! List) return json['summary'] as String? ?? '';
    return c
        .whereType<Map>()
        .where((p) => p['type'] == 'text')
        .map((p) => p['text'] as String? ?? '')
        .join();
  }

  /// The thinking parts joined.
  String get thinking {
    final c = json['content'];
    if (c is! List) return '';
    return c
        .whereType<Map>()
        .where((p) => p['type'] == 'thinking')
        .map((p) => p['thinking'] as String? ?? '')
        .join();
  }

  /// `stop`, `length`, `toolUse`, `error`, `aborted`. Assistant messages only.
  String? get stopReason => json['stopReason'] as String?;

  String? get errorMessage => json['errorMessage'] as String?;

  /// Tool calls the assistant made.
  List<Map<String, Object?>> get toolCalls {
    final c = json['content'];
    if (c is! List) return const [];
    return c
        .whereType<Map>()
        .where((p) => p['type'] == 'toolCall')
        .map((p) => p.cast<String, Object?>())
        .toList();
  }

  /// Token usage, assistant messages only.
  Map<String, Object?>? get usage => (json['usage'] as Map?)?.cast<String, Object?>();
}

/// One entry in a session: a node of pi's append-only tree.
///
/// A branch is the path from the root to a tip; [LlmSession.entries] is the
/// current one, root first. Editing a message or regenerating an answer moves
/// the tip back ([LlmSession.navigate]) and grows a new branch beside the old
/// one, which stays in the tree.
extension type const LlmEntry(Map<String, Object?> json) {
  String get id => json['id'] as String;
  String? get parentId => json['parentId'] as String?;

  /// `message`, `compaction`, `branch_summary` or `custom`.
  String get type => json['type'] as String? ?? '';

  /// Milliseconds since the epoch.
  int get timestamp => json['timestamp'] as int? ?? 0;

  /// Order of writing within the session.
  int get seq => json['seq'] as int? ?? 0;

  /// For `message` entries.
  LlmMessage? get message {
    final m = json['message'];
    return m is Map ? LlmMessage(m.cast<String, Object?>()) : null;
  }

  /// For `compaction` and `branch_summary` entries: what the model sees in
  /// place of what came before.
  String? get summary => json['summary'] as String?;

  /// For `custom` entries: what the app called it, and what it stored.
  String? get customType => json['customType'] as String?;
  Object? get data => json['data'];

  /// For `compaction` entries: tokens in the context before it.
  int? get tokensBefore => json['tokensBefore'] as int?;
}

/// Something that happened in a session, as pi's harness reports it.
///
/// [type] is one of `run_start`, `run_end`, `run_suspend`, `run_resume`,
/// `turn_start`, `turn_end`, `message_start`, `message_update`,
/// `message_end`, `tool_start`, `tool_update`, `tool_end`, `entry_added`,
/// `retry_scheduled`, `retry_start`, `retry_end`, `compaction_start`,
/// `compaction_end`, `navigation_start`, `navigation_end`, `usage`, `fault`,
/// `operation_abort`, `handler_error`. For [FlPiLlm.complete] it is pi-ai's
/// `AssistantMessageEvent` type instead.
final class LlmEvent {
  const LlmEvent(this.type, this.json);

  factory LlmEvent.fromJson(Map<String, Object?> json) =>
      LlmEvent(json['type'] as String? ?? '', json);

  final String type;
  final Map<String, Object?> json;

  /// The `AssistantMessageEvent` inside a `message_update`, or this event
  /// itself for a completion.
  Map<String, Object?> get _ame => type == 'message_update'
      ? (json['event'] as Map?)?.cast<String, Object?>() ?? const {}
      : json;

  /// For `message_update`: e.g. `text_delta`, `thinking_delta`,
  /// `toolcall_delta`.
  String? get updateType => type == 'message_update' ? _ame['type'] as String? : null;

  /// Text added by this event, if it added text.
  String? get textDelta => _ame['type'] == 'text_delta' ? _ame['delta'] as String? : null;

  /// Thinking added by this event, if it added any.
  String? get thinkingDelta => _ame['type'] == 'thinking_delta' ? _ame['delta'] as String? : null;

  /// For `message_start`, `message_end` and `turn_end`.
  LlmMessage? get message {
    final m = json['message'];
    return m is Map ? LlmMessage(m.cast<String, Object?>()) : null;
  }

  /// For `entry_added`.
  LlmEntry? get entry {
    final e = json['entry'];
    return e is Map ? LlmEntry(e.cast<String, Object?>()) : null;
  }

  /// For the `tool_*` events.
  String? get toolCallId => json['toolCallId'] as String?;
  String? get toolName => json['toolName'] as String?;

  /// For `run_end`, `compaction_end`, `navigation_end`: `completed`,
  /// `aborted`, `failed` or `declined`.
  String? get status => json['status'] as String?;

  /// For a failed `run_end` and friends, and `fault`.
  String? get error {
    final e = json['error'];
    if (e is Map) return e['message'] as String?;
    return e as String? ?? json['message'] as String?;
  }

  @override
  String toString() => 'LlmEvent($type)';
}

/// How a run ended.
final class LlmRunResult {
  const LlmRunResult(this.json);

  final Map<String, Object?> json;

  /// `completed`, `aborted`, `failed` or `declined`.
  String get status => json['status'] as String? ?? '';
  bool get completed => status == 'completed';

  String? get error => (json['error'] as Map?)?['message'] as String?;

  /// The branch tip after the run.
  String? get tipId => json['tipId'] as String?;

  @override
  String toString() => 'LlmRunResult($status${error == null ? '' : ': $error'})';
}

/// A stored session.
final class LlmSessionInfo {
  const LlmSessionInfo({required this.id, required this.createdAt, required this.modifiedAt});

  factory LlmSessionInfo.fromJson(Map<String, Object?> j) => LlmSessionInfo(
    id: j['id'] as String,
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int),
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(j['modifiedAt'] as int),
  );

  final String id;
  final DateTime createdAt;
  final DateTime modifiedAt;
}

/// The runtime or a request failed.
final class LlmException implements Exception {
  const LlmException(this.message);

  final String message;

  @override
  String toString() => 'LlmException: $message';
}
