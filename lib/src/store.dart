import 'dart:io';

/// A file in a [PiSessionStore].
final class StoredFile {
  const StoredFile(this.path, this.size, this.modified);

  /// Absolute, POSIX: `/sessions/.../<id>.jsonl`.
  final String path;

  /// In UTF-16 code units or bytes; only compared, never summed.
  final int size;
  final DateTime modified;

  Map<String, Object?> toJson() => {
    'path': path,
    'size': size,
    'mtimeMs': modified.millisecondsSinceEpoch,
  };
}

/// Where pi's sessions are kept.
///
/// pi stores a session as an append-only JSONL file and reaches it through a
/// filesystem it is handed. This is that filesystem, cut down to whole text
/// files by path. Directories are not stored: one exists while a file under
/// it does.
///
/// Implement it over whatever the app already keeps its data in — an
/// encrypted database, say — or use [DirectorySessionStore] or
/// [MemorySessionStore].
abstract interface class PiSessionStore {
  /// The file's text, or `null` when there is no such file. With [maxLines],
  /// at least that many leading lines, when the file has them.
  Future<String?> read(String path, {int? maxLines});

  Future<void> write(String path, String text);

  /// Creates the file when it does not exist.
  Future<void> append(String path, String text);

  Future<void> rename(String from, String to);

  /// A file, or with [recursive] every file under the directory [path].
  Future<void> remove(String path, {bool recursive = false});

  /// `null` when there is no such file.
  Future<StoredFile?> stat(String path);

  /// Every file under [dir], at any depth.
  Future<List<StoredFile>> list(String dir);
}

/// Sessions in memory. For tests, and for conversations nobody keeps.
final class MemorySessionStore implements PiSessionStore {
  final _files = <String, (StringBuffer, DateTime)>{};

  @override
  Future<String?> read(String path, {int? maxLines}) async => _files[path]?.$1.toString();

  @override
  Future<void> write(String path, String text) async =>
      _files[path] = (StringBuffer(text), DateTime.now());

  @override
  Future<void> append(String path, String text) async {
    final f = _files[path];
    _files[path] = ((f?.$1 ?? StringBuffer())..write(text), DateTime.now());
  }

  @override
  Future<void> rename(String from, String to) async {
    final f = _files.remove(from);
    if (f == null) throw FileSystemException('No such file', from);
    _files[to] = f;
  }

  @override
  Future<void> remove(String path, {bool recursive = false}) async {
    _files.remove(path);
    if (recursive) _files.removeWhere((k, _) => k.startsWith('$path/'));
  }

  @override
  Future<StoredFile?> stat(String path) async {
    final f = _files[path];
    return f == null ? null : StoredFile(path, f.$1.length, f.$2);
  }

  @override
  Future<List<StoredFile>> list(String dir) async {
    final prefix = dir == '/' ? '/' : '$dir/';
    return [
      for (final MapEntry(:key, :value) in _files.entries)
        if (key.startsWith(prefix)) StoredFile(key, value.$1.length, value.$2),
    ];
  }
}

/// Sessions as plain JSONL files under [root]. Unencrypted.
final class DirectorySessionStore implements PiSessionStore {
  DirectorySessionStore(this.root);

  final Directory root;

  File _file(String path) => File('${root.path}$path');

  @override
  Future<String?> read(String path, {int? maxLines}) async {
    final f = _file(path);
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  @override
  Future<void> write(String path, String text) async {
    final f = _file(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(text, flush: true);
  }

  @override
  Future<void> append(String path, String text) async {
    final f = _file(path);
    await f.parent.create(recursive: true);
    await f.writeAsString(text, mode: FileMode.append, flush: true);
  }

  @override
  Future<void> rename(String from, String to) async {
    final dest = _file(to);
    await dest.parent.create(recursive: true);
    await _file(from).rename(dest.path);
  }

  @override
  Future<void> remove(String path, {bool recursive = false}) async {
    final type = await FileSystemEntity.type(_file(path).path);
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.directory) {
      await Directory(_file(path).path).delete(recursive: recursive);
    } else {
      await _file(path).delete();
    }
  }

  @override
  Future<StoredFile?> stat(String path) async {
    final s = await _file(path).stat();
    if (s.type != FileSystemEntityType.file) return null;
    return StoredFile(path, s.size, s.modified);
  }

  @override
  Future<List<StoredFile>> list(String dir) async {
    final d = Directory(_file(dir).path);
    if (!await d.exists()) return const [];
    final out = <StoredFile>[];
    await for (final e in d.list(recursive: true)) {
      if (e is! File) continue;
      final s = await e.stat();
      out.add(StoredFile(e.path.substring(root.path.length).replaceAll(r'\', '/'), s.size, s.modified));
    }
    return out;
  }
}
