import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm/fl_pi_llm.dart';
import 'package:fl_pi_llm_ui/src/config.dart';
import 'package:fl_pi_llm_ui/src/core/llm.dart';
import 'package:fl_pi_llm_ui/src/skills/skills.dart';
import 'package:fl_pi_llm_ui/src/core/user_input.dart';
import 'package:fl_pi_llm_ui/src/tools/tool.dart';
import 'package:fl_pi_llm_ui/src/store/chat_meta.dart';
import 'package:fl_pi_llm_ui/src/store/stores.dart';
import 'package:shortid/shortid.dart';

/// The reply being written: what the stream has said so far.
final class StreamingReply {
  const StreamingReply({this.text = '', this.thinking = '', this.tools = const []});

  /// Nothing written yet: no text, no thinking, no tool called.
  bool get isEmpty => text.isEmpty && thinking.isEmpty && tools.isEmpty;

  final String text;
  final String thinking;

  /// Tool calls running now, by name.
  final List<String> tools;

  StreamingReply copyWith({String? text, String? thinking, List<String>? tools}) =>
      StreamingReply(text: text ?? this.text, thinking: thinking ?? this.thinking, tools: tools ?? this.tools);
}

/// A tool call waiting for the user, shown in the chat it belongs to.
final class PendingApproval {
  PendingApproval(this.call);

  final LlmToolCall call;
  final _answer = Completer<LlmApproval>();

  void _complete(LlmApproval a) {
    if (!_answer.isCompleted) _answer.complete(a);
  }
}

/// How the user answered a [PendingApproval].
enum ApprovalAnswer { deny, once, always }

/// A file [Chats.send] cannot attach: not an image, and not text of at most
/// [maxBytes].
final class UnsupportedAttachment implements Exception {
  const UnsupportedAttachment(this.name);

  final String name;
  static const maxBytes = 512 * 1024;

  @override
  String toString() => 'Cannot attach $name: only images and text files up to 512 KB';
}

/// A chat as another device takes it ([Chats.exportChat]): its entries in
/// pi's session-file shape, each after its parent, and the uid of the one it
/// stands on.
typedef ChatExport = ({List<Map<String, Object?>> entries, String? tip});

/// An open chat: its session, and what the chat view draws.
final class OpenChat {
  OpenChat._(this.id, this.session) {
    _sub = session.events.listen(_onEvent);
    running.addListener(Chats.runningChanges.notify);
    approvals.addListener(Chats.runningChanges.notify);
    pendingInput.addListener(Chats.runningChanges.notify);
  }

  final String id;
  final LlmSession session;
  late final StreamSubscription<LlmEvent> _sub;

  /// The end of the current branch, root first: the last page read, and
  /// those before it that [loadEarlier] read.
  final entries = <LlmEntry>[].vn;

  /// Whether the branch goes on before [entries].
  final hasEarlier = false.vn;

  /// How much of a branch a chat shows at first, and [loadEarlier] adds.
  static const pageSize = 60;

  /// While a run is going.
  final running = false.vn;

  /// The reply being streamed, if one is.
  final streaming = nvn<StreamingReply>();

  /// An error the last run ended with.
  final error = nvn<String>();

  /// A run a previous launch left unfinished: [Chats.resume] picks it up.
  final interrupted = false.vn;

  /// How long each reply of this session thought, by entry id, as measured
  /// while it streamed. A reply that also wrote text cannot be timed from its
  /// timestamps alone.
  final thoughtMs = <String, int>{};
  DateTime? _thinkStart, _thinkEnd;

  /// Tool calls the run is waiting on the user for, in the order asked.
  /// The first is the one on screen.
  final approvals = <PendingApproval>[].vn;

  /// A form the model asked the user to fill in (`ask_user`), while it waits.
  final pendingInput = nvn<PendingInput>();

  /// Waiting on the user: a call to approve, or a form to fill in.
  bool get waiting => approvals.value.isNotEmpty || pendingInput.value != null;

  /// Answers every pending call and form: a run is never left waiting.
  void _denyPending(String why) {
    for (final p in approvals.value) {
      p._complete(LlmApproval.deny(why));
    }
    approvals.value = const [];
    pendingInput.value?.complete(const UserInputCancelled());
    pendingInput.value = null;
  }

  /// Reads the end of the branch again, as much of it as was shown.
  Future<void> reload() async {
    final page = await session.page(limit: math.max(pageSize, entries.value.length));
    entries.value = page.entries;
    hasEarlier.value = page.more;
    interrupted.value = session.interrupted;
  }

  Future<void>? _loadingEarlier;

  /// Reads the page before [entries]. One at a time.
  Future<void> loadEarlier() => _loadingEarlier ??= _loadEarlier().whenComplete(() => _loadingEarlier = null);

  Future<void> _loadEarlier() async {
    final first = entries.value.firstOrNull;
    if (first == null || !hasEarlier.value) return;
    final page = await session.page(limit: pageSize, before: first.id);
    // Moved meanwhile — a version switched, a run ended: what was read joins
    // nothing.
    if (entries.value.firstOrNull?.id != first.id) return;
    entries.value = [...page.entries, ...entries.value];
    hasEarlier.value = page.more;
  }

  void _onEvent(LlmEvent e) {
    switch (e.type) {
      case 'message_start' when e.message?.role == 'assistant':
        streaming.value = const StreamingReply();
        _thinkStart = _thinkEnd = null;
      case 'message_update':
        final s = streaming.value ?? const StreamingReply();
        if (e.textDelta case final d?) {
          if (_thinkStart != null) _thinkEnd ??= DateTime.now();
          streaming.value = s.copyWith(text: s.text + d);
        } else if (e.thinkingDelta case final d?) {
          _thinkStart ??= DateTime.now();
          streaming.value = s.copyWith(thinking: s.thinking + d);
        }
      case 'tool_start':
        final s = streaming.value ?? const StreamingReply();
        streaming.value = s.copyWith(tools: [...s.tools, e.toolName ?? '?']);
      case 'entry_added':
        final entry = e.entry;
        if (entry == null) return;
        final list = entries.value;
        if (entry.parentId == list.lastOrNull?.id) entries.value = [...list, entry];
        if (entry.type == 'message' && entry.message?.role == 'assistant') {
          if (_thinkStart case final start?) {
            thoughtMs[entry.id] = (_thinkEnd ?? DateTime.now()).difference(start).inMilliseconds;
          }
          _thinkStart = _thinkEnd = null;
          streaming.value = null;
        }
      case 'run_end':
        streaming.value = null;
        if (e.status == 'failed') error.value = e.error;
    }
  }

  /// The user messages beside [entry], oldest first, itself included.
  List<LlmEntry> _siblings(LlmEntry entry) => entry.versions ?? [entry];

  /// What a user message says, text and images: siblings saying the same are
  /// one message asked again (a regeneration — pi starts every run with a
  /// user message), others are edits.
  static String _said(LlmEntry e) => jsonEncode(e.message?.json['content']);

  /// The versions of the user message [entry] made by editing it: one per
  /// thing said, in the order first said. The one said as [entry] is
  /// [entry]; any other, its latest asking.
  List<LlmEntry> editsOf(LlmEntry entry) {
    final mine = _said(entry);
    final by = <String, LlmEntry>{};
    for (final s in _siblings(entry)) {
      final k = _said(s);
      by[k] = k == mine ? entry : s;
    }
    return by.values.toList();
  }

  /// The replies to the user message [entry]: one per asking of the same
  /// message, oldest first. Regenerating adds one.
  List<LlmEntry> repliesOf(LlmEntry entry) {
    final mine = _said(entry);
    return [
      for (final s in _siblings(entry))
        if (_said(s) == mine) s,
    ];
  }

  Future<void> _dispose() async {
    _denyPending('The chat was closed');
    await _sub.cancel();
    await session.close();
  }
}

/// Chats: the list, the open ones, and everything done to them.
abstract final class Chats {
  static final _open = <String, OpenChat>{};
  static final _opening = <String, Future<OpenChat>>{};

  /// The chat on screen.
  static final current = nvn<String>();

  /// Notified when a chat is opened or closed: what shows its state follows.
  static final openChanges = RNode();

  /// Notified when any chat starts or stops running: for a list of chats that
  /// marks the ones writing a reply, without a listener on each.
  static final runningChanges = RNode();

  /// Whether chat [id] is writing a reply or running a tool.
  static bool isRunning(String id) => _open[id]?.running.value ?? false;

  /// Whether chat [id] is waiting on the user: a call to approve, or a form.
  static bool isWaiting(String id) => _open[id]?.waiting ?? false;

  /// Shows [request] in chat [id] and waits for the user to fill it in or
  /// not. One at a time: a second while one is on screen is refused.
  /// [cancelled] takes this form away, and only this one.
  static Future<UserInputAnswer> ask(String id, UserInputRequest request, {Future<void>? cancelled}) async {
    final chat = _open[id] ?? (throw const LlmException('The chat is not open'));
    if (chat.pendingInput.value != null) throw const LlmException('A form is already waiting on the user');
    final pending = PendingInput(id, request);
    unawaited(cancelled?.then((_) => pending.complete(const UserInputCancelled())));
    chat.pendingInput.value = pending;
    try {
      return await pending.answer;
    } finally {
      if (chat.pendingInput.value == pending) chat.pendingInput.value = null;
    }
  }

  /// Answers chat [id]'s form — see [PendingInput.submit].
  static void submitInput(String id, {Map<String, Object?> answers = const {}, Map<String, Object?> values = const {}}) =>
      _open[id]?.pendingInput.value?.submit(answers: answers, values: values);

  /// Leaves chat [id]'s form unfilled — with [message], what the user sent
  /// instead, for the model to go on from.
  static void cancelInput(String id, {String? message}) =>
      _open[id]?.pendingInput.value?.complete(UserInputCancelled(message: message));

  /// Temporary users of each chat ([borrow]), which close it when done.
  static final _borrows = <String, int>{};

  /// Completed when the last borrow of each chat ends: [close] waits for it.
  static final _borrowed = <String, Completer<void>>{};

  static OpenChat? openOf(String id) => _open[id];

  /// The chat, opened if it is not.
  static Future<OpenChat> open(String id) {
    final c = _open[id];
    if (c != null) return Future.value(c);
    // A block, not an arrow: `remove` returns this very future, and
    // `whenComplete` would wait for it — for itself.
    return _opening[id] ??= _doOpen(id).whenComplete(() {
      _opening.remove(id);
    });
  }

  static Future<OpenChat> _doOpen(String id) async {
    final chat = OpenChat._(id, await _openSession(id));
    try {
      await chat.reload();
    } catch (_) {
      // Or the runtime keeps it, and every later open fails as "already open".
      await chat._dispose();
      rethrow;
    }
    _open[id] = chat;
    openChanges.notify();
    return chat;
  }

  static Future<LlmSession> _openSession(String id) {
    final meta = LlmStores.chat.fetch(id);
    final model = meta?.model ?? Llm.defaultModel;
    if (model == null) throw const LlmException('No model: add a provider key first');
    return Llm.rt.openSession(
      id: id,
      model: model,
      systemPrompt: systemPromptFor(meta),
      tools: _toolsFor(meta),
      thinkingLevel: thinkingFor(model),
      compaction: LlmStores.llm.compaction.get() ? const CompactionSettings() : CompactionSettings.disabled,
      approve: _approve,
    );
  }

  /// Chat [id] for another device ([FlPiLlm.exportSession]): every entry,
  /// each after its parent, and the uid of the one it stands on. The chat need
  /// not be open.
  static Future<ChatExport> exportChat(String id) async {
    final entries = <Map<String, Object?>>[];
    int? after;
    String? tip;
    do {
      final page = await Llm.rt.exportSession(id, after: after);
      entries.addAll(page.entries);
      tip = page.tip;
      after = page.next;
    } while (after != null);
    return (entries: entries, tip: tip);
  }

  /// About how much of a chat one import request carries: the engine's heap
  /// is bounded.
  static const _importChars = 4 << 20;

  /// Writes what [entries], another device's [exportChat] of chat [id], has
  /// and the chat lacks ([FlPiLlm.importSession]); [tip] for a chat new here.
  /// Returns how many entries it wrote. An open chat shows them: now, or when
  /// the reply it is writing ends.
  static Future<int> importChat(String id, List<Map<String, Object?>> entries, {String? tip}) async {
    var added = 0;
    var page = <Map<String, Object?>>[];
    var chars = 0;
    Future<void> send({required bool last}) async {
      final r = await Llm.rt.importSession(id, page, tip: last ? tip : null);
      if (r.orphans.isNotEmpty) Loggers.app.warning('Sync $id: ${r.orphans.length} entries without their parent');
      added += r.added;
      page = [];
      chars = 0;
    }

    for (final e in entries) {
      page.add(e);
      chars += jsonEncode(e).length;
      if (chars >= _importChars) await send(last: false);
    }
    await send(last: true);
    if (added == 0) return 0;
    try {
      await _opening[id];
    } catch (_) {
      // Failed to open: then it is not open.
    }
    final chat = _open[id];
    if (chat != null && !chat.running.value) await chat.reload();
    return added;
  }

  /// Closes chat [id], once what borrowed it ([borrow]) is done with it.
  static Future<void> close(String id) async {
    // Again after each: another may have begun while one ended.
    for (Completer<void>? b; (b = _borrowed[id]) != null;) {
      await b!.future;
    }
    final c = _open.remove(id);
    if (c != null) openChanges.notify();
    LlmSecrets.forget(id);
    // Being closed by another call: done when that is.
    if (c == null) return _closing[id];
    // A borrow begun from here on opens the chat again once this is closed.
    final closing = _closing[id] = c._dispose();
    try {
      await closing;
    } finally {
      if (identical(_closing[id], closing)) _closing.remove(id);
    }
  }

  /// Chats being closed, for [borrow] to wait for.
  static final _closing = <String, Future<void>>{};

  static Future<void> closeAll() async {
    for (final id in [..._open.keys]) {
      await close(id);
    }
  }

  /// Runs [fn] on chat [id], opened for it if it was not, and closed again
  /// after unless something else has taken it up meanwhile: it went on
  /// screen, or started a run.
  static Future<T> borrow<T>(String id, Future<T> Function(OpenChat chat) fn) async {
    final wasOpen = _open.containsKey(id) || _opening.containsKey(id);
    _borrows[id] = (_borrows[id] ?? 0) + 1;
    _borrowed[id] ??= Completer<void>();
    try {
      // Closed or not, it is opened again below.
      await _closing[id]?.then((_) {}, onError: (_) {});
      return await fn(await open(id));
    } finally {
      final n = _borrows[id]! - 1;
      n == 0 ? _borrows.remove(id) : _borrows[id] = n;
      if (n == 0) _borrowed.remove(id)?.complete();
      final c = _open[id];
      if (!wasOpen && n == 0 && c != null && !c.running.value && current.value != id) await close(id);
    }
  }

  /// The chat's current branch as markdown.
  static Future<String> markdownOf(String id) => borrow(id, (c) async => toMarkdown(await c.session.entries()));

  static String toMarkdown(List<LlmEntry> entries) {
    final sb = StringBuffer();
    for (final e in entries) {
      final m = e.message;
      if (m == null) continue;
      final who = switch (m.role) {
        'user' => '👤',
        'assistant' => '🤖',
        _ => null,
      };
      if (who == null) continue;
      sb
        ..writeln('### $who')
        ..writeln()
        ..writeln(m.text)
        ..writeln();
    }
    return sb.toString();
  }

  /// Makes a new chat in [scope] and returns its id. Its session is created
  /// on open.
  static String create({String? scope}) {
    final id = shortid.generate();
    LlmStores.chat.put(ChatMeta(id: id, updatedAt: DateTime.now(), model: Llm.defaultModel, scope: scope));
    return id;
  }

  /// Sends [text], with [files] attached, and runs until the reply is done.
  static Future<void> send(String id, String text, {List<String> files = const []}) async {
    final chat = await open(id);
    _claim(chat);
    final (String, List<Map<String, Object?>>) composed;
    try {
      composed = await _compose(text, files);
    } catch (_) {
      chat.running.value = false;
      rethrow;
    }
    final (prompt, images) = composed;
    await _run(chat, () => chat.session.prompt(prompt, images: images.isEmpty ? null : images));
    _touch(id);
    unawaited(_maybeTitle(chat, text));
  }

  /// Sends [text] in place of the user message [entry]; the old one stays as
  /// another version.
  static Future<void> edit(String id, LlmEntry entry, String text) async {
    final chat = await open(id);
    _claim(chat);
    final images = _imagesOf(entry.message);
    await _run(chat, () async {
      await chat.session.navigate(entry.parentId);
      await chat.reload();
      return chat.session.prompt(text, images: images.isEmpty ? null : images);
    });
    _touch(id);
  }

  /// Asks for another reply to the user message [entry].
  static Future<void> regenerate(String id, LlmEntry entry) =>
      edit(id, entry, entry.message?.text ?? '');

  /// Asks again after the last run failed: the last user message, again.
  static Future<void> retry(String id) async {
    final chat = await open(id);
    final user = chat.entries.value.lastWhereOrNull((e) => e.message?.role == 'user');
    if (user != null) await regenerate(id, user);
  }

  /// Carries on the run a previous launch left unfinished.
  static Future<void> resume(String id) async {
    final chat = await open(id);
    _claim(chat);
    await _run(chat, chat.session.resume);
    _touch(id);
  }

  /// Shows the version [entry] of a message, and the conversation that
  /// followed it.
  static Future<void> switchTo(String id, LlmEntry entry) async {
    final chat = await open(id);
    await chat.session.switchTo(entry.id);
    await chat.reload();
  }

  static Future<void> abort(String id) async {
    final chat = _open[id];
    chat?._denyPending('The user stopped the reply');
    await chat?.session.abort();
  }

  /// Answers the tool call chat [id] is waiting on.
  static void answer(String id, ApprovalAnswer answer) {
    final chat = _open[id];
    final pending = chat?.approvals.value.firstOrNull;
    if (chat == null || pending == null) return;
    chat.approvals.value = chat.approvals.value.skip(1).toList();
    switch (answer) {
      case ApprovalAnswer.always:
        // Remembered only for a tool that offers it — see [ToolFunc.allowAlways].
        if (Tools.internal(pending.call.name)?.allowAlways ?? true) {
          LlmStores.tool.permittedTools.set({...LlmStores.tool.permittedTools.get(), pending.call.name}.toList());
        }
        pending._complete(const LlmApproval.allow());
      case ApprovalAnswer.once:
        pending._complete(const LlmApproval.allow());
      case ApprovalAnswer.deny:
        pending._complete(const LlmApproval.deny('The user denied it'));
    }
  }

  /// Answers the tool call chat [id] is waiting on with [approval] itself —
  /// a deny whose reason says what the user did instead, say. For the choices
  /// a [ToolFunc.preview] adds to the approval card.
  static void decide(String id, LlmApproval approval) {
    final chat = _open[id];
    final pending = chat?.approvals.value.firstOrNull;
    if (chat == null || pending == null) return;
    chat.approvals.value = chat.approvals.value.skip(1).toList();
    pending._complete(approval);
  }

  /// Marks [chat] as running, or refuses: one run at a time. Synchronous
  /// after the open, so two sends a moment apart cannot both start one.
  static void _claim(OpenChat chat) {
    if (chat.running.value) throw const LlmException('A reply is still being written');
    chat.error.value = null;
    chat.running.value = true;
  }

  /// Runs [run] on [chat], which [_claim] has marked running.
  static Future<void> _run(OpenChat chat, Future<LlmRunResult> Function() run) async {
    try {
      final r = await run();
      if (r.status == 'failed') chat.error.value = r.error;
    } catch (e, s) {
      Loggers.app.warning('Run in ${chat.id}', e, s);
      chat.error.value = '$e';
    } finally {
      chat.running.value = false;
      chat.streaming.value = null;
      // Closed meanwhile (trashed, say): nothing to show.
      if (_open[chat.id] == chat) {
        try {
          await chat.reload();
        } catch (e, s) {
          Loggers.app.warning('Reload ${chat.id}', e, s);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Notices

  static const _noticeTag = 'app_notice';

  /// Tells the model in chat [id] that [text] happened — something it started
  /// finished, say — and lets it answer. Written as a user turn, the only
  /// kind a model is prompted with, but marked: the view draws it as the
  /// app's notice rather than as the user's words, and the system prompt
  /// says what the mark means. Waits for a reply being written to end.
  static Future<void> notify(String id, String text) async {
    if (LlmStores.chat.fetch(id) == null) return;
    final chat = await open(id);
    bool closed() => !identical(_open[id], chat);
    while (chat.running.value && !closed()) {
      // Idle, or closed while it ran: a closed chat never runs again.
      final settled = Completer<void>();
      void done() {
        if ((!chat.running.value || closed()) && !settled.isCompleted) settled.complete();
      }
      chat.running.addListener(done);
      openChanges.addListener(done);
      await settled.future;
      chat.running.removeListener(done);
      openChanges.removeListener(done);
    }
    // Closed meanwhile — trashed, say: nothing to tell.
    if (closed()) return;
    _claim(chat);
    _touch(id);
    await _run(chat, () => chat.session.prompt('<$_noticeTag>\n$text\n</$_noticeTag>'));
  }

  /// [m]'s text, when it is one of [notify]'s rather than the user's.
  static String? noticeOf(LlmMessage m) {
    if (m.role != 'user') return null;
    final t = m.text.trim();
    const open = '<$_noticeTag>', close = '</$_noticeTag>';
    if (!t.startsWith(open) || !t.endsWith(close)) return null;
    return t.substring(open.length, t.length - close.length).trim();
  }

  static String get _noticePrompt =>
      'A user message wrapped in <$_noticeTag> comes from the app, not from the user: it reports something that '
      'happened, such as a task you started having finished. Act on it as the task calls for; the user may not be '
      'watching.';

  static void _touch(String id) {
    final meta = LlmStores.chat.fetch(id);
    if (meta != null) LlmStores.chat.put(meta.copyWith(updatedAt: DateTime.now()));
  }

  // ---------------------------------------------------------------------------
  // The chat list

  static void rename(String id, String title) {
    final meta = LlmStores.chat.fetch(id);
    if (meta != null) LlmStores.chat.put(meta.copyWith(title: title));
  }

  static Future<void> setModel(String id, LlmModelRef model) async {
    final meta = LlmStores.chat.fetch(id);
    if (meta != null) LlmStores.chat.put(meta.copyWith(model: model));
    final c = _open[id];
    if (c != null) {
      await c.session.setModel(model);
      await c.session.setThinkingLevel(thinkingFor(model));
    }
  }

  static Future<void> setUseTools(String id, bool use) async {
    final meta = LlmStores.chat.fetch(id);
    if (meta == null) return;
    final next = meta.copyWith(useTools: use);
    LlmStores.chat.put(next);
    await _open[id]?.session.setTools(_toolsFor(next));
  }

  static Future<void> trash(String id) async {
    await close(id);
    final meta = LlmStores.chat.fetch(id);
    if (meta != null) LlmStores.chat.put(meta.copyWith(trashedAt: DateTime.now()));
  }

  static void restore(String id) {
    final meta = LlmStores.chat.fetch(id);
    if (meta != null) LlmStores.chat.put(meta.copyWith(restore: true, updatedAt: DateTime.now()));
  }

  static Future<void> deleteForever(String id) async {
    await close(id);
    LlmStores.chat.delete(id);
    try {
      await Llm.rt.deleteSession(id);
    } catch (e, s) {
      // A chat that never sent anything has no session.
      Loggers.app.fine('Delete session $id: $e', null, s);
    }
  }

  /// Deletes what has been in the trash longer than the setting allows.
  static Future<void> purgeTrash() async {
    final keep = Duration(days: LlmUi.trashDays());
    final now = DateTime.now();
    for (final m in LlmStores.chat.all(trashed: true, anyScope: true)) {
      if (now.difference(m.trashedAt!) > keep) await deleteForever(m.id);
    }
  }

  /// Chats in [scope] whose title or conversation contains [query], newest
  /// first.
  static Future<List<ChatMeta>> search(String query, {String? scope}) async {
    final q = query.toLowerCase();
    final hits = await Llm.sessionsContaining(query);
    final all = LlmStores.chat.all(scope: scope);
    return [
      for (final m in all)
        if ((m.title?.toLowerCase().contains(q) ?? false) || hits.contains(m.id)) m,
    ];
  }

  // ---------------------------------------------------------------------------
  // Settings applied to open sessions

  /// The system prompt of [meta]'s chat: the user's, the app's, the memory,
  /// and the skills.
  ///
  /// Read when a chat opens or is reconfigured, not on every memory write:
  /// what the model saves mid-chat it already knows, and a prompt that stays
  /// put keeps the provider's prompt cache.
  static String systemPromptFor(ChatMeta? meta) {
    // The tools the switch is about, not the loader of skills nor the form.
    final tools = _toolsFor(meta).any((t) => t.name != TfSkill.instance.name && t.name != TfAskUser.instance.name);
    return [
      LlmStores.llm.systemPrompt.get(),
      ?LlmUi.appPrompt(meta),
      _noticePrompt,
      if (Tools.memoryOn) ?TfMemory.prompt(tools: tools),
      if (tools) ?McpTools.instructions,
      if (Tools.skillsOffered(meta)) ?Skills.prompt(),
    ].where((e) => e.isNotEmpty).join('\n\n');
  }

  static Timer? _reconfigureTimer;

  /// [reconfigure], once things have stopped changing for a moment.
  static void reconfigureSoon() {
    _reconfigureTimer?.cancel();
    _reconfigureTimer = Timer(const Duration(milliseconds: 300), () => unawaited(reconfigure()));
  }

  /// Applies the system prompt, tools and compaction to every open chat.
  static Future<void> reconfigure() async {
    for (final c in [..._open.values]) {
      try {
        final meta = LlmStores.chat.fetch(c.id);
        await c.session.setSystemPrompt(systemPromptFor(meta));
        await c.session.setTools(_toolsFor(meta));
        await c.session.setCompaction(
          LlmStores.llm.compaction.get() ? const CompactionSettings() : CompactionSettings.disabled,
        );
      } catch (e, s) {
        Loggers.app.warning('Reconfigure ${c.id}', e, s);
      }
    }
  }

  static List<LlmTool> _toolsFor(ChatMeta? meta) {
    // Off for this chat: the tools, not the skills nor asking the user.
    if (meta?.useTools == false) {
      return [
        if (Tools.skillsOffered(meta)) TfSkill.instance.llmTool,
        if (LlmUi.offers(meta, TfAskUser.groupName)) TfAskUser.instance.llmTool,
      ];
    }
    return Tools.enabledFor(meta);
  }

  /// The level [model] thinks at: the one picked, or the nearest it takes.
  static ThinkingLevel thinkingFor(LlmModelRef? model) {
    final info = Llm.info(model);
    if (info == null || !info.reasoning) return ThinkingLevel.off;
    final picked = ThinkingLevel.values.asNameMap()[LlmStores.llm.thinkingLevel.get()] ?? ThinkingLevel.medium;
    return info.clampThinking(picked);
  }

  static Future<void> setThinkingLevel(ThinkingLevel level) async {
    LlmStores.llm.thinkingLevel.set(level.name);
    for (final c in [..._open.values]) {
      final model = LlmStores.chat.fetch(c.id)?.model ?? Llm.defaultModel;
      if (model != null) await c.session.setThinkingLevel(thinkingFor(model));
    }
  }

  static Future<LlmApproval> _approve(LlmToolCall call) async {
    final tool = Tools.internal(call.name);
    if (tool?.trusted ?? false) return const LlmApproval.allow();
    try {
      if (await tool?.preApprove(call.args, call.sessionId) case final decided?) return decided;
    } catch (e, s) {
      // Not decided, then: the user is asked, which is never the unsafe way.
      Loggers.app.warning('Pre-approve ${call.name}', e, s);
    }
    if ((tool?.allowAlways ?? true) && LlmStores.tool.permittedTools.get().contains(call.name)) {
      return const LlmApproval.allow();
    }
    // A chat's id is its session's: the question goes where the run is.
    final chat = _open[call.sessionId];
    if (chat == null) return const LlmApproval.deny('The chat is not open');
    final pending = PendingApproval(call);
    chat.approvals.value = [...chat.approvals.value, pending];
    return pending._answer.future;
  }

  // ---------------------------------------------------------------------------
  // Titles

  static const _titlePrompt =
      'Name this conversation in at most 8 words, in the language the user writes in. '
      'Reply with the title only: no quotes, no punctuation at the end.';

  static Future<void> _maybeTitle(OpenChat chat, String firstText) async {
    if (!LlmUi.genTitle()) return;
    final meta = LlmStores.chat.fetch(chat.id);
    if (meta == null || meta.title != null) return;
    final model = LlmStores.llm.titleModel.get() ?? meta.model ?? Llm.defaultModel;
    if (model == null) return;
    try {
      final reply = chat.entries.value.lastWhereOrNull((e) => e.message?.role == 'assistant')?.message?.text ?? '';
      final m = await Llm.rt.complete(
        model: model,
        systemPrompt: _titlePrompt,
        messages: [
          LlmMessage({
            'role': 'user',
            'content': 'User: $firstText\n\nAssistant: ${reply.length > 800 ? reply.substring(0, 800) : reply}',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
          }),
        ],
      );
      final title = m.text.trim().replaceAll(RegExp(r'^["“《]|["”》]$'), '').split('\n').first;
      // Not over one the user gave it while this was being asked.
      if (title.isNotEmpty && LlmStores.chat.fetch(chat.id)?.title == null) rename(chat.id, title);
    } catch (e, s) {
      Loggers.app.info('Title of ${chat.id}', e, s);
    }
  }

  // ---------------------------------------------------------------------------
  // Attachments

  /// The prompt text with text files inlined, and the images as pi parts.
  static Future<(String, List<Map<String, Object?>>)> _compose(String text, List<String> files) async {
    final images = <Map<String, Object?>>[];
    final inlined = <String>[];
    for (final path in files) {
      final file = File(path);
      if (!await file.exists()) continue;
      final name = file.uri.pathSegments.last;
      final mime = await file.mimeType ?? '';
      if (mime.startsWith('image/')) {
        images.add(LlmContent.image(base64Encode(await file.readAsBytes()), mime));
        continue;
      }
      if (await file.length() > UnsupportedAttachment.maxBytes) throw UnsupportedAttachment(name);
      try {
        inlined.add('<file name="$name">\n${await file.readAsString()}\n</file>');
      } on FormatException {
        throw UnsupportedAttachment(name);
      }
    }
    return ([...inlined, text].join('\n\n'), images);
  }

  static List<Map<String, Object?>> _imagesOf(LlmMessage? m) {
    final c = m?.json['content'];
    if (c is! List) return const [];
    return [
      for (final p in c.whereType<Map>())
        if (p['type'] == 'image') p.cast<String, Object?>(),
    ];
  }
}
