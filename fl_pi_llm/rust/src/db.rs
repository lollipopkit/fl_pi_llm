//! Where chats are kept: one SQLite file per chat, holding pi-durable's
//! `SqliteStorage` (`js/src/db.js`), under the directory the host names:
//!
//!   <dir>/chats/<id>.db   a chat
//!   <dir>/cache.db        what can be fetched again: the model lists
//!
//! A chat is queried, never loaded: opening one reads what is shown, however
//! long it has grown. The SQL runs here, on the engine thread or on whatever
//! thread searches, so nothing of it reaches the host's UI thread.
//!
//! With a [Key], every file is encrypted (SQLite3 Multiple Ciphers, built by
//! `build.rs`): what the user and the model said is never on disk in clear.

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use rusqlite::functions::FunctionFlags;
use rusqlite::{Connection, OpenFlags, params};

const SUFFIX: &str = ".db";
/// SQLite's own files beside a database, removed with it.
const COMPANIONS: [&str; 3] = ["-wal", "-shm", "-journal"];

/// The file name of chat [id]: anything but `[A-Za-z0-9_-]` percent-encoded,
/// so an id never names a path elsewhere, and `.` never starts one.
pub fn file_name(id: &str) -> String {
    let mut out = String::with_capacity(id.len() + SUFFIX.len());
    for b in id.bytes() {
        if b.is_ascii_alphanumeric() || b == b'_' || b == b'-' {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out.push_str(SUFFIX);
    out
}

/// The chat a [file_name] belongs to.
pub fn id_of(name: &str) -> Option<String> {
    let stem = name.strip_suffix(SUFFIX)?;
    let bytes = stem.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' {
            let hex = std::str::from_utf8(bytes.get(i + 1..i + 3)?).ok()?;
            out.push(u8::from_str_radix(hex, 16).ok()?);
            i += 3;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    let id = String::from_utf8(out).ok()?;
    (file_name(&id) == name).then_some(id)
}

/// What the chats are encrypted with: 32 random bytes, kept by the host in
/// the platform's keychain. Used as is, without a key derivation: the bytes
/// are already a key, and every open would pay for one.
#[derive(Clone)]
pub struct Key([u8; 32]);

impl Key {
    pub fn new(bytes: &[u8]) -> Result<Self, String> {
        let bytes: [u8; 32] = bytes.try_into().map_err(|_| format!("a chat key is 32 bytes, not {}", bytes.len()))?;
        Ok(Self(bytes))
    }

    /// The `PRAGMA key` and `rekey` value: a raw key, `x'…'`.
    fn pragma(&self) -> String {
        let hex: String = self.0.iter().map(|b| format!("{b:02x}")).collect();
        format!("\"x'{hex}'\"")
    }
}

impl std::fmt::Debug for Key {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Key(..)")
    }
}

/// Where chats are kept, and what they are encrypted with: in clear without
/// a key.
#[derive(Clone, Debug)]
pub struct Storage {
    pub root: PathBuf,
    pub key: Option<Key>,
}

/// SQLite3 Multiple Ciphers' default, the one fl_lib's store uses too.
const CIPHER: &str = "chacha20";

/// Whether [e] says the file is not a database: encrypted with another key,
/// or not encrypted.
fn not_a_database(e: &rusqlite::Error) -> bool {
    matches!(e, rusqlite::Error::SqliteFailure(f, _) if f.code == rusqlite::ErrorCode::NotADatabase)
}

/// Keys [conn], before anything reads a page, and reads one: a wrong key
/// fails here rather than as an empty chat.
fn unlock(conn: &Connection, key: &Key) -> rusqlite::Result<()> {
    conn.execute_batch(&format!("PRAGMA cipher = '{CIPHER}'; PRAGMA key = {};", key.pragma()))?;
    conn.query_row("SELECT count(*) FROM sqlite_master", [], |_| Ok(()))?;
    // A SQLite without the cipher takes the pragmas and encrypts nothing.
    conn.query_row("SELECT sqlite3mc_version()", [], |_| Ok(()))
}

/// Encrypts the file at [path], one written in clear before chats were
/// encrypted. `rekey` takes no WAL database: the journal is folded in first.
///
/// TODO: remove once no install keeps a chat from before encryption (Server
/// Box's Agent chats, development builds of GPT Box).
fn encrypt(path: &Path, key: &Key) -> rusqlite::Result<()> {
    let conn = Connection::open(path)?;
    conn.query_row("SELECT count(*) FROM sqlite_master", [], |_| Ok(()))?;
    conn.pragma_update(None, "journal_mode", "DELETE")?;
    conn.execute_batch(&format!("PRAGMA cipher = '{CIPHER}'; PRAGMA rekey = {};", key.pragma()))
}

/// Opens the file at [path], keyed with [key], creating it when there is
/// none; one in clear is encrypted first.
fn connect(path: &Path, key: Option<&Key>, flags: OpenFlags) -> rusqlite::Result<Connection> {
    let conn = Connection::open_with_flags(path, flags)?;
    let Some(key) = key else { return Ok(conn) };
    match unlock(&conn, key) {
        Err(e) if not_a_database(&e) => {
            drop(conn);
            encrypt(path, key)?;
            let conn = Connection::open_with_flags(path, flags)?;
            unlock(&conn, key)?;
            Ok(conn)
        }
        r => r.map(|()| conn),
    }
}

/// A stored chat.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StoredChat {
    pub id: String,
    pub created_at_ms: u64,
    pub modified_at_ms: u64,
}

fn now_ms() -> u64 {
    ms(SystemTime::now())
}

fn ms(t: SystemTime) -> u64 {
    t.duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64)
}

fn configure(conn: &Connection) -> rusqlite::Result<()> {
    conn.busy_timeout(Duration::from_secs(5))?;
    conn.set_prepared_statement_cache_capacity(64);
    // Commits survive the app being killed; the newest may be lost with power.
    conn.pragma_update(None, "journal_mode", "WAL")?;
    conn.pragma_update(None, "synchronous", "NORMAL")
}

/// Opens chat [id] under [dir], creating it when there is none.
pub fn open(dir: &Path, id: &str, key: Option<&Key>) -> Result<Connection, String> {
    std::fs::create_dir_all(dir).map_err(|e| format!("chat directory {}: {e}", dir.display()))?;
    let init = || -> rusqlite::Result<Connection> {
        let conn = connect(&dir.join(file_name(id)), key, OpenFlags::default())?;
        configure(&conn)?;
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS fl_chat (
                singleton  INTEGER PRIMARY KEY CHECK (singleton = 1),
                created_at INTEGER NOT NULL
            ) STRICT;
            -- The ids entries are known by on every device (`js/src/sync.js`),
            -- for those pi-durable wrote, which carry none in their record.
            CREATE TABLE IF NOT EXISTS fl_uid (
                id  INTEGER PRIMARY KEY,
                uid TEXT NOT NULL UNIQUE
            ) STRICT;",
        )?;
        conn.execute("INSERT OR IGNORE INTO fl_chat (singleton, created_at) VALUES (1, ?1)", params![now_ms() as i64])?;
        Ok(conn)
    };
    init().map_err(|e| format!("open chat {id}: {e}"))
}

/// For reading beside the engine. Not `SQLITE_OPEN_READ_ONLY`: a WAL database
/// is read through its `-shm`, which that cannot create.
fn open_read_only(path: &Path, key: Option<&Key>) -> rusqlite::Result<Connection> {
    let conn = connect(path, key, OpenFlags::SQLITE_OPEN_READ_WRITE | OpenFlags::SQLITE_OPEN_NO_MUTEX)?;
    conn.busy_timeout(Duration::from_secs(5))?;
    conn.pragma_update(None, "query_only", true)?;
    Ok(conn)
}

/// Every chat under [dir]. [key] reads when each was made; a chat it cannot
/// be read with is listed as made when it was last written.
pub fn list(dir: &Path, key: Option<&Key>) -> Result<Vec<StoredChat>, String> {
    let entries = match std::fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
        Err(e) => return Err(format!("list chats: {e}")),
    };
    let mut out = Vec::new();
    for entry in entries.flatten() {
        let name = entry.file_name();
        let Some(id) = name.to_str().and_then(id_of) else { continue };
        let path = entry.path();
        let modified_at_ms = std::iter::once(path.clone())
            .chain(COMPANIONS.iter().map(|s| companion(&path, s)))
            .filter_map(|p| std::fs::metadata(p).and_then(|m| m.modified()).ok())
            .map(ms)
            .max()
            .unwrap_or(0);
        let created_at_ms = open_read_only(&path, key)
            .and_then(|c| c.query_row("SELECT created_at FROM fl_chat", [], |r| r.get::<_, i64>(0)))
            .map_or(modified_at_ms, |v| v as u64);
        out.push(StoredChat { id, created_at_ms, modified_at_ms });
    }
    Ok(out)
}

fn companion(path: &Path, suffix: &str) -> PathBuf {
    let mut s = path.as_os_str().to_owned();
    s.push(suffix);
    PathBuf::from(s)
}

/// Deletes chat [id]. It must not be open.
pub fn remove(dir: &Path, id: &str) -> Result<(), String> {
    let path = dir.join(file_name(id));
    for p in std::iter::once(path.clone()).chain(COMPANIONS.iter().map(|s| companion(&path, s))) {
        match std::fs::remove_file(&p) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
            Err(e) => return Err(format!("delete chat {id}: {e}")),
        }
    }
    Ok(())
}

/// What the user and the model said: the text parts of `user` and
/// `assistant` messages, not the stored JSON around them. `CASE` keeps a
/// string from reaching `json_extract`, which takes it for malformed JSON.
const SAID: &str = "
SELECT 1 FROM entries e, json_each(e.record, '$.model') m
WHERE m.type = 'object' AND json_extract(m.value, '$.role') IN ('user', 'assistant') AND EXISTS (
  SELECT 1 FROM json_each(m.value, '$.content') c
  WHERE fl_contains(CASE
    WHEN c.type = 'text' THEN c.value
    WHEN c.type = 'object' AND json_extract(c.value, '$.type') = 'text' THEN json_extract(c.value, '$.text')
  END, ?1)
)
LIMIT 1";

/// The chats under [storage] where [needle] was said, ignoring case.
pub fn search(storage: &Storage, needle: &str) -> Result<Vec<String>, String> {
    let dir = &chats_dir(&storage.root);
    let key = storage.key.as_ref();
    let needle = needle.to_lowercase();
    let mut out = Vec::new();
    for chat in list(dir, key)? {
        let found = open_read_only(&dir.join(file_name(&chat.id)), key).and_then(|conn| {
            conn.create_scalar_function("fl_contains", 2, FunctionFlags::SQLITE_UTF8 | FunctionFlags::SQLITE_DETERMINISTIC, |ctx| {
                let hay = ctx.get_raw(0).as_str_or_null()?.unwrap_or_default();
                let needle = ctx.get_raw(1).as_str()?;
                Ok(hay.to_lowercase().contains(needle))
            })?;
            match conn.query_row(SAID, params![needle], |_| Ok(())) {
                Ok(()) => Ok(true),
                Err(rusqlite::Error::QueryReturnedNoRows) => Ok(false),
                // Created but never written to by pi: nothing said.
                Err(rusqlite::Error::SqliteFailure(_, Some(m))) if m.starts_with("no such table") => Ok(false),
                Err(e) => Err(e),
            }
        });
        match found {
            Ok(true) => out.push(chat.id),
            Ok(false) => {}
            Err(e) => return Err(format!("search chat {}: {e}", chat.id)),
        }
    }
    Ok(out)
}

fn chats_dir(root: &Path) -> PathBuf {
    root.join("chats")
}

/// The databases the engine has open, by handle.
pub struct Chats {
    storage: Option<Storage>,
    /// By handle, with the chat each is of.
    open: HashMap<u32, (String, Connection)>,
    next: u32,
    cache: Option<Connection>,
}

impl Chats {
    /// In the host's [storage]; without one, nothing can be stored.
    pub fn new(storage: Option<Storage>) -> Self {
        Self { storage, open: HashMap::new(), next: 1, cache: None }
    }

    fn storage(&self) -> Result<&Storage, String> {
        self.storage.as_ref().ok_or_else(|| "no storage directory: the host started the runtime without one".into())
    }

    fn key(&self) -> Option<&Key> {
        self.storage.as_ref().and_then(|s| s.key.as_ref())
    }

    fn dir(&self) -> Result<PathBuf, String> {
        self.storage().map(|s| chats_dir(&s.root))
    }

    pub fn open(&mut self, id: &str) -> Result<u32, String> {
        let conn = open(&self.dir()?, id, self.key())?;
        let mut h = self.next;
        // Wrapped around: past the handles still open.
        while self.open.contains_key(&h) {
            h = h.wrapping_add(1).max(1);
        }
        self.next = h.wrapping_add(1).max(1);
        self.open.insert(h, (id.to_string(), conn));
        Ok(h)
    }

    pub fn close(&mut self, h: u32) {
        self.open.remove(&h);
    }

    pub fn get(&self, h: u32) -> Result<&Connection, String> {
        self.open.get(&h).map(|(_, c)| c).ok_or_else(|| format!("chat database {h} is not open"))
    }

    pub fn list(&self) -> Result<Vec<StoredChat>, String> {
        list(&self.dir()?, self.key())
    }

    /// Refused while a handle to it is open: the file would go from under it.
    pub fn remove(&self, id: &str) -> Result<(), String> {
        if self.open.values().any(|(open, _)| open == id) {
            return Err(format!("chat {id} is open"));
        }
        remove(&self.dir()?, id)
    }

    fn cache(&mut self) -> Result<&Connection, String> {
        if self.cache.is_none() {
            let root = &self.storage()?.root;
            std::fs::create_dir_all(root).map_err(|e| format!("storage directory {}: {e}", root.display()))?;
            let path = root.join("cache.db");
            // What it holds can be fetched again: one this key does not open
            // (encrypted with a key since lost) is started over.
            let opened = match connect(&path, self.key(), OpenFlags::default()) {
                Err(e) if not_a_database(&e) => {
                    for p in std::iter::once(path.clone()).chain(COMPANIONS.iter().map(|s| companion(&path, s))) {
                        let _ = std::fs::remove_file(p);
                    }
                    connect(&path, self.key(), OpenFlags::default())
                }
                r => r,
            };
            let conn = opened
                .and_then(|conn| {
                    configure(&conn)?;
                    conn.execute_batch("CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, value TEXT NOT NULL) STRICT;")?;
                    Ok(conn)
                })
                .map_err(|e| format!("open cache: {e}"))?;
            self.cache = Some(conn);
        }
        Ok(self.cache.as_ref().expect("opened above"))
    }

    pub fn cache_get(&mut self, key: &str) -> Result<Option<String>, String> {
        match self.cache()?.query_row("SELECT value FROM cache WHERE key = ?1", [key], |r| r.get(0)) {
            Ok(v) => Ok(Some(v)),
            Err(rusqlite::Error::QueryReturnedNoRows) => Ok(None),
            Err(e) => Err(format!("read cache: {e}")),
        }
    }

    /// Sets [key]; `None` removes it.
    pub fn cache_set(&mut self, key: &str, value: Option<&str>) -> Result<(), String> {
        let conn = self.cache()?;
        match value {
            Some(v) => conn.execute("INSERT INTO cache (key, value) VALUES (?1, ?2) ON CONFLICT (key) DO UPDATE SET value = ?2", params![key, v]),
            None => conn.execute("DELETE FROM cache WHERE key = ?1", [key]),
        }
        .map(drop)
        .map_err(|e| format!("write cache: {e}"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_round_trip_and_stay_in_the_directory() {
        for id in ["abc", "-QBjtZW188", "a/b", "..", ".", "中文 id", "x%41", "a.b"] {
            let name = file_name(id);
            assert!(!name.contains('/') && !name.starts_with('.'), "{name}");
            assert_eq!(id_of(&name).as_deref(), Some(id));
        }
        assert_eq!(id_of("abc.db-wal"), None);
        assert_eq!(id_of("%61.db"), None, "not what file_name writes");
    }

    fn temp_dir(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("fl_pi_llm_db_{name}_{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&d);
        d
    }

    fn key(byte: u8) -> Key {
        Key::new(&[byte; 32]).unwrap()
    }

    /// A chat with an `entries` table of [records], as pi-durable keeps them.
    fn chat_with(dir: &Path, id: &str, key: Option<&Key>, records: &[&str]) {
        let conn = open(dir, id, key).unwrap();
        conn.execute_batch("CREATE TABLE entries (id INTEGER PRIMARY KEY, record TEXT NOT NULL);").unwrap();
        for r in records {
            conn.execute("INSERT INTO entries (record) VALUES (?1)", [r]).unwrap();
        }
    }

    /// The bytes of chat [id]'s files, its WAL included.
    fn bytes_of(dir: &Path, id: &str) -> Vec<u8> {
        let path = dir.join(file_name(id));
        [path.clone(), companion(&path, "-wal")].iter().filter_map(|p| std::fs::read(p).ok()).flatten().collect()
    }

    fn contains(hay: &[u8], needle: &[u8]) -> bool {
        hay.windows(needle.len()).any(|w| w == needle)
    }

    #[test]
    fn lists_searches_and_removes() {
        let root = temp_dir("search");
        let storage = Storage { root: root.clone(), key: Some(key(7)) };
        let dir = chats_dir(&root);
        chat_with(&dir, "c/1", storage.key.as_ref(), &[
            r#"{"model":[{"role":"user","content":"Hello ÄBC"}]}"#,
            r#"{"model":[{"role":"assistant","content":[{"type":"text","text":"needle here"},{"type":"image","data":"zzz"}]}]}"#,
            r#"{"model":[{"role":"toolResult","content":[{"type":"text","text":"hidden"}]}]}"#,
            r#"{"kind":"pi.system"}"#,
        ]);
        drop(open(&dir, "empty", storage.key.as_ref()).unwrap());

        let mut ids: Vec<_> = list(&dir, storage.key.as_ref()).unwrap().into_iter().map(|c| c.id).collect();
        ids.sort();
        assert_eq!(ids, ["c/1", "empty"]);
        assert_eq!(search(&storage, "äbc").unwrap(), ["c/1"]);
        assert_eq!(search(&storage, "NEEDLE").unwrap(), ["c/1"]);
        assert!(search(&storage, "hidden").unwrap().is_empty(), "tool output is not what was said");
        assert!(search(&storage, "zzz").unwrap().is_empty(), "nor is an image");

        remove(&dir, "c/1").unwrap();
        assert_eq!(list(&dir, storage.key.as_ref()).unwrap().len(), 1);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_chat_is_encrypted_and_opens_with_its_key_alone() {
        let root = temp_dir("encrypted");
        let dir = chats_dir(&root);
        chat_with(&dir, "c", Some(&key(1)), &[r#"{"model":[{"role":"user","content":"secret words"}]}"#]);
        let bytes = bytes_of(&dir, "c");
        assert!(!bytes.is_empty());
        assert!(!contains(&bytes, b"secret words"), "what was said is not on disk in clear");
        assert!(!contains(&bytes, b"SQLite format 3"), "nor is the database's header");

        let err = open(&dir, "c", Some(&key(2))).unwrap_err();
        assert!(err.contains("not a database"), "{err}");
        assert!(open(&dir, "c", None).is_err(), "nor read without one");
        let found = search(&Storage { root: root.clone(), key: Some(key(1)) }, "SECRET").unwrap();
        assert_eq!(found, ["c"]);
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_chat_in_clear_is_encrypted_when_opened_with_a_key() {
        let root = temp_dir("clear");
        let dir = chats_dir(&root);
        chat_with(&dir, "c", None, &[r#"{"model":[{"role":"user","content":"old words"}]}"#]);
        assert!(contains(&bytes_of(&dir, "c"), b"old words"));

        let conn = open(&dir, "c", Some(&key(3))).unwrap();
        let n: i64 = conn.query_row("SELECT count(*) FROM entries", [], |r| r.get(0)).unwrap();
        assert_eq!(n, 1, "nothing lost");
        drop(conn);
        assert!(!contains(&bytes_of(&dir, "c"), b"old words"));
        assert!(open(&dir, "c", None).is_err());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn an_open_chat_is_not_removed() {
        let root = temp_dir("open");
        let mut chats = Chats::new(Some(Storage { root: root.clone(), key: Some(key(5)) }));
        let h = chats.open("c").unwrap();
        assert_eq!(chats.remove("c").unwrap_err(), "chat c is open");
        assert_eq!(chats.list().unwrap().len(), 1);
        chats.close(h);
        chats.remove("c").unwrap();
        assert!(chats.list().unwrap().is_empty());
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn caches_beside_the_chats() {
        let root = temp_dir("cache");
        let mut chats = Chats::new(Some(Storage { root: root.clone(), key: Some(key(5)) }));
        assert_eq!(chats.cache_get("k").unwrap(), None);
        chats.cache_set("k", Some("v1")).unwrap();
        chats.cache_set("k", Some("v2")).unwrap();
        assert_eq!(chats.cache_get("k").unwrap().as_deref(), Some("v2"));
        chats.cache_set("k", None).unwrap();
        assert_eq!(chats.cache_get("k").unwrap(), None);
        assert!(chats.list().unwrap().is_empty(), "the cache is not a chat");
        chats.cache_set("k", Some("v")).unwrap();
        drop(chats);
        // Under another key: started over rather than failing.
        let mut chats = Chats::new(Some(Storage { root: root.clone(), key: Some(key(6)) }));
        assert_eq!(chats.cache_get("k").unwrap(), None);
        let _ = std::fs::remove_dir_all(&root);
    }
}
