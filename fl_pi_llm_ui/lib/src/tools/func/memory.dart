part of '../tool.dart';

/// The memory tools: files under `/memories` ([MemoryStore]), read and
/// written by the model across chats. What they do, say and accept is
/// [LlmMemory]'s (fl_pi_llm, shared with every host); this is their place
/// among the app's tools. One switch for all of them, and no approval: they
/// touch nothing but the memory, which the user can see and edit in the
/// settings.
sealed class TfMemory extends ToolFunc {
  const TfMemory({required super.name}) : super(parametersSchema: const {});

  /// The switch in [ToolStore.disabledTools] for every memory tool.
  static const groupName = 'memory';

  static const all = <TfMemory>[
    TfMemoryView.instance,
    TfMemorySearch.instance,
    TfMemoryWrite.instance,
    TfMemoryEdit.instance,
    TfMemoryDelete.instance,
    TfMemoryMove.instance,
  ];

  LlmMemoryTool get _spec => LlmMemory.tools.firstWhere((t) => t.name == name);

  @override
  _Map get parametersSchema => _spec.parameters;

  @override
  String get description => _spec.description;

  @override
  String get group => groupName;

  @override
  String get groupLabel => llmL10n.memory;

  @override
  bool get trusted => true;

  @override
  String summary(_Map args) => '${args['path'] ?? args['from'] ?? MemoryStore.root}';

  @override
  Future<LlmToolResult> run(_Map args, ToolCtx ctx) async => LlmToolResult.text(LlmStores.memory.run(name, args));

  /// The memory's part of the system prompt: how to use it when [tools] are
  /// on, the files, and the index. Null when there is nothing to say.
  static String? prompt({required bool tools}) => LlmMemory.prompt(LlmStores.memory.all(), tools: tools);
}

final class TfMemoryView extends TfMemory {
  static const instance = TfMemoryView._();

  const TfMemoryView._() : super(name: 'memory_view');

  @override
  String get l10nName => llmL10n.memoryView;
}

final class TfMemorySearch extends TfMemory {
  static const instance = TfMemorySearch._();

  const TfMemorySearch._() : super(name: 'memory_search');

  @override
  String get l10nName => llmL10n.memorySearch;

  @override
  String summary(_Map args) => '${args['query'] ?? ''}';
}

final class TfMemoryWrite extends TfMemory {
  static const instance = TfMemoryWrite._();

  const TfMemoryWrite._() : super(name: 'memory_write');

  @override
  String get l10nName => llmL10n.memoryWrite;
}

final class TfMemoryEdit extends TfMemory {
  static const instance = TfMemoryEdit._();

  const TfMemoryEdit._() : super(name: 'memory_edit');

  @override
  String get l10nName => llmL10n.memoryEdit;
}

final class TfMemoryDelete extends TfMemory {
  static const instance = TfMemoryDelete._();

  const TfMemoryDelete._() : super(name: 'memory_delete');

  @override
  String get l10nName => llmL10n.memoryDelete;
}

final class TfMemoryMove extends TfMemory {
  static const instance = TfMemoryMove._();

  const TfMemoryMove._() : super(name: 'memory_move');

  @override
  String get l10nName => llmL10n.memoryMove;

  @override
  String summary(_Map args) => '${args['from'] ?? ''} → ${args['to'] ?? ''}';
}
