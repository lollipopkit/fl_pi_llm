//! Compiles SQLite3 Multiple Ciphers, the SQLite the chats are kept with
//! (`src/db.rs`), and the JS bundle to QuickJS bytecode, so the app does not
//! parse 1.3 MB of JavaScript on every launch.
//!
//! The bundle is compiled by the host's QuickJS — the same crate version as the target's,
//! pinned by `Cargo.lock` — and written little-endian, which every target is.
//! 32-bit targets load the source instead: the bytecode is only known to be
//! portable between targets of the same word size.

use std::path::PathBuf;

use rquickjs::module::WriteOptions;
use rquickjs::{Context, Module, Runtime};

const BUNDLE: &str = "js/fl_pi_llm.js";

fn main() {
    sqlite();
    println!("cargo:rerun-if-changed={BUNDLE}");
    // Room for Flutter to rewrite the dylib's install name to where it copies
    // it: the linker leaves only what the build-time path needs, and
    // `install_name_tool` fails on a longer one (a checkout in a deeper
    // directory than the Cargo target dir).
    if std::env::var("CARGO_CFG_TARGET_VENDOR").as_deref() == Ok("apple") {
        println!("cargo:rustc-cdylib-link-arg=-Wl,-headerpad_max_install_names");
    }
    let out = PathBuf::from(std::env::var("OUT_DIR").unwrap()).join("fl_pi_llm.qbc");
    if std::env::var("CARGO_CFG_TARGET_POINTER_WIDTH").as_deref() != Ok("64") {
        std::fs::write(&out, []).unwrap();
        return;
    }
    let source = std::fs::read_to_string(BUNDLE).expect("the JS bundle; run `npm run build` in js/");
    let rt = Runtime::new().unwrap();
    let ctx = Context::full(&rt).unwrap();
    let bytes = ctx.with(|ctx| {
        let module = Module::declare(ctx.clone(), "fl_pi_llm", source).unwrap_or_else(|e| {
            panic!("compiling the bundle: {e}: {:?}", ctx.catch());
        });
        module
            .write(WriteOptions { strip_source: true, ..Default::default() })
            .expect("writing bytecode")
    });
    std::fs::write(&out, bytes).unwrap();
}

/// rusqlite links no SQLite of its own (`in_gecko`): this one, which encrypts.
/// For every crate of the build: a host's own libsqlite3-sys users (sqlx in
/// Server Box's monitor) get it too. So it is built with the options of
/// libsqlite3-sys's bundled SQLite, and unlock notification, which sqlx asks
/// for.
fn sqlite() {
    let dir = sqlite3mc_src::source_dir();
    let android = std::env::var("CARGO_CFG_TARGET_OS").as_deref() == Ok("android");
    let mut build = cc::Build::new();
    build.file(dir.join(sqlite3mc_src::SOURCE_FILE)).include(dir);
    for define in [
        "SQLITE_CORE",
        "SQLITE_DEFAULT_FOREIGN_KEYS=1",
        "SQLITE_ENABLE_API_ARMOR",
        "SQLITE_ENABLE_COLUMN_METADATA",
        "SQLITE_ENABLE_DBSTAT_VTAB",
        "SQLITE_ENABLE_FTS3",
        "SQLITE_ENABLE_FTS3_PARENTHESIS",
        "SQLITE_ENABLE_FTS5",
        "SQLITE_ENABLE_JSON1",
        "SQLITE_ENABLE_LOAD_EXTENSION=1",
        "SQLITE_ENABLE_MEMORY_MANAGEMENT",
        "SQLITE_ENABLE_RTREE",
        "SQLITE_ENABLE_STAT4",
        "SQLITE_ENABLE_UNLOCK_NOTIFY",
        "SQLITE_SOUNDEX",
        "SQLITE_THREADSAFE=1",
        "SQLITE_USE_URI",
        "HAVE_USLEEP=1",
        "HAVE_ISNAN",
        "_POSIX_THREAD_SAFE_FUNCTIONS",
    ] {
        match define.split_once('=') {
            Some((k, v)) => build.define(k, v),
            None => build.define(define, None),
        };
    }
    // Temporary tables are not encrypted: kept in memory, never on disk.
    // Android, where SQLite finds no temporary directory, always so.
    build.define("SQLITE_TEMP_STORE", if android { "3" } else { "2" });
    build.warnings(false).compile("sqlite3mc");
}
