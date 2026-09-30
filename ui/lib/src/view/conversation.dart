import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/config.dart';
import 'package:fl_pi_llm_ui/src/core/chats.dart';
import 'package:fl_pi_llm_ui/src/res/l10n.dart';
import 'package:fl_pi_llm_ui/src/view/message.dart';
import 'package:fl_pi_llm_ui/src/view/pull_actions.dart';
import 'package:material_ui/material_ui.dart';

/// A chat's conversation: its thread, the reply being written, the tool
/// call waiting on the user, and what went wrong. Opens the chat.
class LlmConversation extends StatefulWidget {
  const LlmConversation({super.key, required this.chatId, this.pullDown, this.pullUp});

  final String chatId;

  /// What pulling down past the top does, and pulling up past the end.
  final PullAction? pullDown;
  final PullAction? pullUp;

  @override
  State<LlmConversation> createState() => _LlmConversationState();
}

class _LlmConversationState extends State<LlmConversation> {
  late final Future<OpenChat> _open = Chats.open(widget.chatId);
  final _scroll = ScrollController();

  /// Whether the view is at the bottom, and so follows new content.
  var _atBottom = true;

  /// The last entry seen: a new message from the user scrolls down to it
  /// wherever the view was.
  String? _lastEntry;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (!_scroll.hasClients) return;
      _atBottom = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 48;
    });
    _open.then((c) {
      c.streaming.addListener(_follow);
      c.entries.addListener(_follow);
      c.approvals.addListener(_follow);
      _lastEntry = c.entries.value.lastOrNull?.id;
      if (LlmUi.scrollAfterSwitch() || c.entries.value.length < 3) _jumpToEnd();
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _open.then((c) {
      c.streaming.removeListener(_follow);
      c.entries.removeListener(_follow);
      c.approvals.removeListener(_follow);
    }, onError: (_) {});
    _scroll.dispose();
    super.dispose();
  }

  void _follow() {
    final chat = Chats.openOf(widget.chatId);
    final last = chat?.entries.value.lastOrNull;
    if (last != null && last.id != _lastEntry) {
      _lastEntry = last.id;
      if (last.message?.role == 'user') {
        _jumpToEnd();
        return;
      }
    }
    if (_atBottom && LlmUi.scrollBottom()) _jumpToEnd();
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<OpenChat>(
      future: _open,
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyPane(icon: Icons.error_outline, title: libL10n.error, label: '${snap.error}');
        }
        final chat = snap.data;
        if (chat == null) return const Center(child: SizedLoading(25, padding: 3, builder: SizedLoading.circularBuilder));
        // Not on each streamed token: that is the last block's alone.
        return ListenableBuilder(
          listenable: Listenable.merge([chat.entries, chat.error, chat.approvals, chat.running, chat.interrupted]),
          builder: (context, _) {
            final blocks = threadBlocks(chat.entries.value);
            final error = chat.error.value;
            final pending = chat.approvals.value.firstOrNull;
            final lastIsReply = blocks.lastOrNull is ReplyBlock;
            Widget view(int i, ThreadBlock b, [StreamingReply? streaming]) => ThreadBlockView(
              key: ValueKey(switch (b) {
                UserBlock(:final entry) || SummaryBlock(:final entry) => entry.id,
                ReplyBlock(:final entries) => entries.first.id,
              }),
              chat: chat,
              block: b,
              streaming: streaming,
              live: chat.running.value && i == blocks.length - 1,
            );
            final items = <Widget>[
              for (final (i, b) in blocks.indexed)
                if (i < blocks.length - 1) view(i, b),
              // The reply being written continues the last reply, or starts
              // one under the last block.
              chat.streaming.listenVal((streamed) {
                // Running with nothing streamed yet — the request is out and
                // the model has not started, or a turn ended and the next is
                // on its way — is still a reply being written, and an empty
                // one draws as the spinner. Not while a call waits on the user.
                final s = streamed ?? (chat.running.value && pending == null ? const StreamingReply() : null);
                final last = blocks.lastOrNull;
                final lastView = last == null ? null : view(blocks.length - 1, last, lastIsReply ? s : null);
                if (s == null || lastIsReply) return lastView ?? UIs.placeholder;
                final stream = StreamingView(reply: s);
                if (lastView == null) return stream;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [lastView, const SizedBox(height: 20), stream],
                );
              }),
              if (pending != null) ApprovalCard(chatId: chat.id, pending: pending),
              if (!chat.running.value && error != null)
                _Notice(
                  text: error,
                  color: context.theme.colorScheme.error,
                  action: libL10n.retry,
                  onTap: () => _guard(Chats.retry(chat.id)),
                )
              else if (!chat.running.value && chat.interrupted.value)
                _Notice(
                  text: llmL10n.replyInterrupted,
                  action: llmL10n.resumeReply,
                  onTap: () => _guard(Chats.resume(chat.id)),
                ),
            ];
            return LayoutBuilder(
              builder: (context, cons) {
                final side = (cons.maxWidth * 0.04).clamp(13.0, 26.0);
                final pulls = widget.pullDown != null || widget.pullUp != null;
                final list = ListView.separated(
                  controller: _scroll,
                  physics: pulls ? PullActions.physics : null,
                  padding: EdgeInsets.fromLTRB(side, 17, side, 26),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 20),
                  itemBuilder: (_, i) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: SizedBox(width: double.infinity, child: items[i]),
                    ),
                  ),
                );
                if (!pulls) return list;
                return PullActions(top: widget.pullDown, bottom: widget.pullUp, child: list);
              },
            );
          },
        );
      },
    );
  }
}

/// A failure is a toast, not an unhandled error.
void _guard(Future<void> f) => f.catchError((Object e) {
  Loggers.app.warning('Chat', e);
  Toast.show('$e');
});

/// A line under the conversation, with what can be done about it.
class _Notice extends StatelessWidget {
  const _Notice({required this.text, required this.action, required this.onTap, this.color});

  final String text;
  final String action;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: color ?? context.theme.hintColor))),
        Btn.text(text: action, onTap: onTap),
      ],
    );
  }
}
