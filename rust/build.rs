//! Compiles the JS bundle to QuickJS bytecode, so the app does not parse
//! 1.3 MB of JavaScript on every launch.
//!
//! Compiled by the host's QuickJS — the same crate version as the target's,
//! pinned by `Cargo.lock` — and written little-endian, which every target is.
//! 32-bit targets load the source instead: the bytecode is only known to be
//! portable between targets of the same word size.

use std::path::PathBuf;

use rquickjs::module::WriteOptions;
use rquickjs::{Context, Module, Runtime};

const BUNDLE: &str = "js/fl_pi_llm.js";

fn main() {
    println!("cargo:rerun-if-changed={BUNDLE}");
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
