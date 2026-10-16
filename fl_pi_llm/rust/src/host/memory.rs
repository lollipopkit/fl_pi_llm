//! The memory (`crate::memory`) for a Rust host: its files kept by the host
//! ([`MemoryBackend`]), its tools run as [`Tool`]s, one change at a time.

use std::sync::Arc;

use serde_json::Value;
use tokio::sync::Mutex;

pub use crate::memory::{is_memory_tool, key_of, path_of, Change, MemoryFile, INDEX, MAX_FILES, MAX_FILE_CHARS, ROOT};
use crate::memory::{self as core, ToolSpec};

use super::{BoxFuture, Cancel, Tool, ToolCall, ToolDef, ToolResult};

/// Why a change to a memory was refused, or could not be made.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MemoryError {
    /// The change is not one the memory takes: told to the model and the user.
    Invalid(String),
    /// Where the files live failed.
    Backend(String),
}

impl std::fmt::Display for MemoryError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            MemoryError::Invalid(m) | MemoryError::Backend(m) => f.write_str(m),
        }
    }
}

impl std::error::Error for MemoryError {}

/// Where a memory's files live. Rows only: what may be written is decided by
/// the memory.
pub trait MemoryBackend: Send + Sync {
    /// Every file, in any order.
    fn list(&self) -> BoxFuture<'_, Result<Vec<MemoryFile>, String>>;
    /// Makes [change], all or none.
    fn apply(&self, change: Change) -> BoxFuture<'_, Result<(), String>>;
}

/// One memory. Its changes are made one at a time, so share one per memory.
pub struct Memory {
    backend: Arc<dyn MemoryBackend>,
    lock: Mutex<()>,
}

impl Memory {
    pub fn new(backend: Arc<dyn MemoryBackend>) -> Self {
        Self { backend, lock: Mutex::new(()) }
    }

    /// Every file, sorted by key.
    pub async fn files(&self) -> Result<Vec<MemoryFile>, MemoryError> {
        let mut files = self.backend.list().await.map_err(MemoryError::Backend)?;
        files.sort_by(|a, b| a.key.cmp(&b.key));
        Ok(files)
    }

    pub async fn read(&self, key: &str) -> Result<Option<MemoryFile>, MemoryError> {
        Ok(self.files().await?.into_iter().find(|f| f.key == key))
    }

    /// Decides a change on the files as they are and makes it, with no other
    /// change in between.
    async fn change<T>(&self, decide: impl FnOnce(&[MemoryFile]) -> Result<(Change, T), String>) -> Result<T, MemoryError> {
        let _one = self.lock.lock().await;
        let files = self.files().await?;
        let (change, out) = decide(&files).map_err(MemoryError::Invalid)?;
        if !change.is_empty() {
            self.backend.apply(change).await.map_err(MemoryError::Backend)?;
        }
        Ok(out)
    }

    /// Writes [content] to the file at [key], creating it.
    pub async fn write(&self, key: &str, content: &str) -> Result<(), MemoryError> {
        self.change(|files| Ok((core::write(files, key, content)?, ()))).await
    }

    /// Deletes the file or directory at [key]; how many files went.
    pub async fn delete(&self, key: &str) -> Result<usize, MemoryError> {
        self.change(|files| {
            let c = core::delete(files, key);
            let n = c.remove.len();
            Ok((c, n))
        })
        .await
    }

    /// Runs the memory tool [name] with [args]: what the model is told.
    pub async fn run(&self, name: &str, args: &Value) -> Result<String, MemoryError> {
        self.change(|files| core::run(files, name, args).map(|o| (o.change, o.text))).await
    }

    /// The memory's part of the system prompt — see [`core::prompt`].
    pub async fn prompt(&self, tools: bool) -> Result<Option<String>, MemoryError> {
        Ok(core::prompt(&self.files().await?, tools))
    }
}

/// The memory tools over [memory], run unasked: they touch nothing but the
/// memory, which the user can see and edit.
pub fn tools(memory: Arc<Memory>) -> Vec<Arc<dyn Tool>> {
    core::tools().into_iter().map(|spec| Arc::new(MemoryTool { spec, memory: memory.clone() }) as Arc<dyn Tool>).collect()
}

struct MemoryTool {
    spec: ToolSpec,
    memory: Arc<Memory>,
}

impl Tool for MemoryTool {
    fn def(&self) -> ToolDef {
        ToolDef {
            name: self.spec.name.into(),
            description: self.spec.description.into(),
            parameters: self.spec.parameters.clone(),
            label: Some(self.spec.label.into()),
            sequential: false,
        }
    }

    fn execute(&self, call: ToolCall, _cancel: Cancel) -> BoxFuture<'_, Result<ToolResult, String>> {
        Box::pin(async move { self.memory.run(self.spec.name, &call.args).await.map(ToolResult::text).map_err(|e| e.to_string()) })
    }
}

/// A memory kept in this process: for tests.
#[derive(Default)]
pub struct InMemoryBackend(std::sync::Mutex<Vec<MemoryFile>>);

impl MemoryBackend for InMemoryBackend {
    fn list(&self) -> BoxFuture<'_, Result<Vec<MemoryFile>, String>> {
        let files = self.0.lock().unwrap().clone();
        Box::pin(async move { Ok(files) })
    }

    fn apply(&self, change: Change) -> BoxFuture<'_, Result<(), String>> {
        {
            let mut files = self.0.lock().unwrap();
            files.retain(|f| !change.remove.contains(&f.key) && !change.put.iter().any(|(k, _)| *k == f.key));
            files.extend(change.put.into_iter().map(|(key, content)| MemoryFile { key, content, modified: Some(0) }));
        }
        Box::pin(async { Ok(()) })
    }
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;

    #[tokio::test]
    async fn a_tool_changes_the_memory_through_its_backend() {
        let m = Arc::new(Memory::new(Arc::new(InMemoryBackend::default())));
        let tool = tools(m.clone()).into_iter().find(|t| t.def().name == "memory_write").unwrap();
        let call = ToolCall { session_id: "s".into(), id: "c".into(), name: "memory_write".into(), args: json!({ "path": "a.md", "content": "x" }) };
        let r = tool.execute(call, Cancel::new()).await.unwrap();
        assert_eq!(r.content[0]["text"], "Created /memories/a.md");
        assert_eq!(m.read("a.md").await.unwrap().unwrap().content, "x");
        assert_eq!(m.write("a.md/b", "y").await.unwrap_err(), MemoryError::Invalid("/memories/a.md is a file".into()));
        assert_eq!(m.delete("a.md").await.unwrap(), 1);
        assert_eq!(m.files().await.unwrap(), []);
    }
}
