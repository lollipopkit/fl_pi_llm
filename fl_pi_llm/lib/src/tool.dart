import 'dart:async';

/// A tool call from the model, as the host sees it.
final class LlmToolCall {
  const LlmToolCall({
    required this.sessionId,
    required this.id,
    required this.name,
    required this.args,
  });

  final String sessionId;
  final String id;
  final String name;

  /// Already validated against the tool's `parameters`.
  final Map<String, Object?> args;

  @override
  String toString() => 'LlmToolCall($name, $id)';
}

/// What a tool returns to the model.
final class LlmToolResult {
  const LlmToolResult({this.content = const [], this.details, this.terminate = false});

  /// A single text part.
  factory LlmToolResult.text(String text, {Object? details}) =>
      LlmToolResult(content: [LlmContent.text(text)], details: details);

  /// pi `TextContent` / `ImageContent` parts. See [LlmContent].
  final List<Map<String, Object?>> content;

  /// Kept with the result for the UI; not sent to the model.
  final Object? details;

  /// Asks the agent to stop after this batch of tool calls.
  final bool terminate;

  Map<String, Object?> toJson() => {
    'content': content,
    'details': details,
    if (terminate) 'terminate': true,
  };
}

/// Builders for pi content parts.
abstract final class LlmContent {
  static Map<String, Object?> text(String text) => {'type': 'text', 'text': text};

  /// [data] is base64, without a `data:` prefix.
  static Map<String, Object?> image(String data, String mimeType) => {
    'type': 'image',
    'data': data,
    'mimeType': mimeType,
  };
}

/// Why a tool call no longer matters: the run was aborted.
final class LlmCancelToken {
  final _completer = Completer<void>();

  bool get isCancelled => _completer.isCompleted;

  /// Completes when the call is cancelled.
  Future<void> get whenCancelled => _completer.future;

  void cancel() {
    if (!_completer.isCompleted) _completer.complete();
  }
}

/// Runs a tool. Throw to report a failure to the model.
typedef LlmToolExecutor =
    Future<LlmToolResult> Function(LlmToolCall call, LlmCancelToken cancel);

/// A tool the model may call. Executed in Dart.
final class LlmTool {
  const LlmTool({
    required this.name,
    required this.description,
    required this.execute,
    this.parameters = const {'type': 'object', 'properties': <String, Object?>{}},
    this.label,
    this.sequential = false,
  });

  final String name;
  final String description;

  /// JSON Schema of the arguments.
  final Map<String, Object?> parameters;

  /// Shown in a UI; defaults to [name].
  final String? label;

  /// Never run alongside other tool calls.
  final bool sequential;

  final LlmToolExecutor execute;

  Map<String, Object?> toJson() => {
    'name': name,
    'description': description,
    'parameters': parameters,
    'label': ?label,
    if (sequential) 'executionMode': 'sequential',
  };
}

/// The user's answer to a tool call awaiting approval.
final class LlmApproval {
  const LlmApproval.allow() : allowed = true, reason = null;

  const LlmApproval.deny([this.reason]) : allowed = false;

  final bool allowed;

  /// Told to the model when denied.
  final String? reason;
}

/// Decides whether a tool call may run. Suspends the run until answered.
typedef LlmApprover = Future<LlmApproval> Function(LlmToolCall call);
