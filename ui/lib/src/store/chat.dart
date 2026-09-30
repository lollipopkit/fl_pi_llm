import 'package:fl_lib/fl_lib.dart';
import 'package:fl_pi_llm_ui/src/store/chat_meta.dart';

/// The chat list: one [ChatMeta] per chat, keyed by its id.
final class ChatStore extends SqliteStore {
  ChatStore._() : super('chats');

  static final instance = ChatStore._();

  /// Notified on every change, for the chat list.
  final changes = RNode();

  /// Every chat in [scope], newest first: the app's own list when null.
  /// [anyScope] for every chat there is, whatever it belongs to.
  List<ChatMeta> all({bool trashed = false, String? scope, bool anyScope = false}) {
    final out = <ChatMeta>[];
    // One query: the list is read on every change.
    for (final MapEntry(:key, :value) in getAllMap().entries) {
      final m = _decode(key, value);
      if (m == null || m.trashed != trashed) continue;
      if (anyScope || m.scope == scope) out.add(m);
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  ChatMeta? fetch(String id) => _decode(id, get<Object>(id));

  static ChatMeta? _decode(String id, Object? v) {
    if (v is! Map) return null;
    try {
      return ChatMeta.fromJson(v.cast<String, Object?>());
    } catch (e) {
      Loggers.app.warning('Chat $id is unreadable', e);
      return null;
    }
  }

  void put(ChatMeta meta) {
    set(meta.id, meta.toJson());
    changes.notify();
  }

  void delete(String id) {
    remove(id);
    changes.notify();
  }
}
