import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart' hide RequestOptions;
import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Icons;
import 'package:fl_pi_llm_ui/src/store/chat_meta.dart';
import 'package:fl_pi_llm_ui/src/core/chats.dart';
import 'package:fl_pi_llm_ui/src/config.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:fl_pi_llm_ui/src/store/memory.dart';
import 'package:fl_pi_llm_ui/src/store/tool.dart';
import 'package:fl_pi_llm_ui/src/skills/skills.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:logging/logging.dart' as logging;
import 'package:mcp_dart/mcp_dart.dart';

part 'type.dart';
part 'func/iface.dart';
part 'func/http.dart';
part 'func/html_text.dart';
part 'func/memory.dart';
part 'func/history.dart';
part 'func/skill.dart';
part 'mcp.dart';
part 'mcp_auth.dart';

/// The tools a chat offers the model: the built-in ones, the app's own
/// ([LlmUi.appTools]), and every tool of every connected MCP server.
abstract final class Tools {
  static const internalTools = <ToolFunc>[
    ...TfMemory.all,
    ...TfHistory.all,
    TfHttpReq.instance,
  ];

  /// The group every MCP tool is under, for [LlmUi.offers].
  static const mcpGroup = 'mcp';

  /// Every tool the app has: built into this package or into the app.
  static List<ToolFunc> get all => [...internalTools, ...LlmUi.appTools()];

  /// One tool of each group: what the settings list, one switch each.
  static List<ToolFunc> get groups {
    final all = Tools.all;
    return [
      for (final (i, t) in all.indexed)
        if (all.indexWhere((e) => e.group == t.group) == i) t,
    ];
  }

  /// What the model gets in a chat of the app's own list — see [enabledFor].
  static List<LlmTool> get enabled => enabledFor(null);

  /// What the model gets in [meta]'s chat: the tools when they are on at
  /// all, and the loader of skills when one is on, which is not a tool the
  /// switch is about.
  static List<LlmTool> enabledFor(ChatMeta? meta) {
    final tools = LlmStores.tool.enabled.get();
    return [
      if (tools)
        for (final t in all)
          if (isOn(t) && LlmUi.offers(meta, t.group)) t.llmTool,
      if (tools && LlmUi.offers(meta, mcpGroup)) ...McpTools.llmTools,
      if (skillsOffered(meta)) TfSkill.instance.llmTool,
    ];
  }

  /// Whether [meta]'s chat is told of the skills and can load them.
  static bool skillsOffered(ChatMeta? meta) => Skills.enabled.isNotEmpty && LlmUi.offers(meta, TfSkill.groupName);

  /// Whether [t]'s switch is on.
  static bool isOn(ToolFunc t) => t.defaultEnabled
      ? !LlmStores.tool.disabledTools.get().contains(t.group)
      : LlmStores.tool.enabledTools.get().contains(t.group);

  /// Turns [t]'s switch, and every tool's under it, [on] or off.
  static void setOn(ToolFunc t, bool on) {
    final prop = t.defaultEnabled ? LlmStores.tool.disabledTools : LlmStores.tool.enabledTools;
    final add = t.defaultEnabled ? !on : on;
    final rest = prop.get().where((e) => e != t.group);
    prop.set([...rest, if (add) t.group]);
  }

  /// Whether the memory tools are switched on; the memory is in the system
  /// prompt only then.
  static bool get memoryOn => isOn(TfMemory.all.first);

  /// The tool named [name], built into this package or into the app.
  static ToolFunc? internal(String name) =>
      name == TfSkill.instance.name ? TfSkill.instance : all.firstWhereOrNull((e) => e.name == name);

  /// Runs [run] and keeps how long it took in the result's `details`, which
  /// the session stores with it for the UI (`ms`).
  static Future<LlmToolResult> timed(Future<LlmToolResult> Function() run) async {
    final sw = Stopwatch()..start();
    final r = await run();
    return LlmToolResult(
      content: r.content,
      details: {...?(r.details as Map?)?.cast<String, Object?>(), 'ms': sw.elapsedMilliseconds},
      terminate: r.terminate,
    );
  }

  /// A tool's name as the user reads it: the built-in one's own, an MCP
  /// tool's as `server__tool` has it.
  static String labelOf(String name) => internal(name)?.l10nName ?? McpTools.toolLabel(name) ?? name;

  /// A call's arguments on one line.
  static String summaryOf(String name, Map<String, Object?> args) =>
      internal(name)?.summary(args) ?? jsonEncode(args);
}
