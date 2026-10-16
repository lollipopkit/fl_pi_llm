//! The memory (`crate::memory`) for the apps, which keep its files: each
//! call is handed the files and answers with what to change. JSON strings, as
//! the rest of the bridge: a file is `{key, content, modified?}`.

use flutter_rust_bridge::frb;
use serde_json::{json, Value};

use crate::memory::{self, MemoryFile};

fn files_of(json: &str) -> anyhow::Result<Vec<MemoryFile>> {
    let v: Vec<Value> = serde_json::from_str(json)?;
    v.into_iter()
        .map(|f| {
            Ok(MemoryFile {
                key: f["key"].as_str().ok_or_else(|| anyhow::anyhow!("a file without a key"))?.to_string(),
                content: f["content"].as_str().ok_or_else(|| anyhow::anyhow!("a file without content"))?.to_string(),
                modified: f["modified"].as_i64(),
            })
        })
        .collect()
}

/// [path] as a memory key — see `memory::key_of`: `{ok: true, key}`, or
/// `{ok: false, error}` with why it is refused.
#[frb(sync)]
pub fn memory_key_of(path: String) -> String {
    match memory::key_of(&path) {
        Ok(key) => json!({ "ok": true, "key": key }),
        Err(error) => json!({ "ok": false, "error": error }),
    }
    .to_string()
}

/// The memory tools: `[{name, label, description, parameters}]`.
#[frb(sync)]
pub fn memory_tools() -> String {
    let tools: Vec<Value> = memory::tools()
        .into_iter()
        .map(|t| json!({ "name": t.name, "label": t.label, "description": t.description, "parameters": t.parameters }))
        .collect();
    Value::Array(tools).to_string()
}

/// The memory's part of the system prompt over [files].
#[frb(sync)]
pub fn memory_prompt(files: String, tools: bool) -> anyhow::Result<Option<String>> {
    Ok(memory::prompt(&files_of(&files)?, tools))
}

/// Runs the memory tool [name] with [args] (JSON) on [files]:
/// `{ok: true, text, put: [[key, content]], remove: [key]}`, or `{ok:
/// false, error}` for the tool's failure, told to the model as it is.
#[frb(sync)]
pub fn memory_run(files: String, name: String, args: String) -> anyhow::Result<String> {
    let files = files_of(&files)?;
    let args: Value = serde_json::from_str(&args)?;
    Ok(match memory::run(&files, &name, &args) {
        Ok(o) => json!({ "ok": true, "text": o.text, "put": o.change.put, "remove": o.change.remove }),
        Err(error) => json!({ "ok": false, "error": error }),
    }
    .to_string())
}
