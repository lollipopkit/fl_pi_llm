//! pi for a Rust program: the host half that `lib/src/runtime.dart` is for
//! Dart. The network ([`Fetch`]), where chats are kept ([`Config::dir`]), the
//! credentials ([`Credentials`]), the tools ([`Tool`]) and the approval of a
//! tool call ([`Approver`]) are the program's; the agent loop is pi's, the
//! same bundle the apps run, so a session written here is one an app can
//! read and the other way round.
//!
//! Payloads stay JSON ([`serde_json::Value`]), as they are on the Dart side:
//! what pi sends is pi's, and a change there is not a change here.
//!
//! Needs a Tokio runtime: [`Runtime::start`] spawns the task that answers the
//! engine.

mod fetch;
pub mod mcp;
pub mod memory;
pub mod skills;

use std::collections::HashMap;
use std::future::Future;
use std::pin::Pin;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, Weak};

use serde_json::{json, Value};
use tokio::sync::{mpsc, oneshot, Notify};

pub use fetch::{fetch_allowed, Fetch, FetchRequest, FetchResponse};
#[cfg(feature = "reqwest")]
pub use fetch::ReqwestFetch;

use crate::engine::{Engine, Inbound, Outbound};

pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// What went wrong: pi's error message, or the runtime being gone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Error(pub String);

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0)
    }
}

impl std::error::Error for Error {}

pub type Result<T> = std::result::Result<T, Error>;

/// Provider credentials, pi-ai's `CredentialStore`: a credential is pi's JSON
/// (`{type: "api_key", key}`).
pub trait Credentials: Send + Sync {
    fn read(&self, provider_id: &str) -> BoxFuture<'_, std::result::Result<Option<Value>, String>>;
    fn list(&self) -> BoxFuture<'_, std::result::Result<Vec<String>, String>>;
    fn write(&self, provider_id: &str, credential: Value) -> BoxFuture<'_, std::result::Result<(), String>>;
    fn delete(&self, provider_id: &str) -> BoxFuture<'_, std::result::Result<(), String>>;
}

/// No stored credentials: every provider gets its key from the model
/// reference (`apiKey`), or has none.
pub struct NoCredentials;

impl Credentials for NoCredentials {
    fn read(&self, _: &str) -> BoxFuture<'_, std::result::Result<Option<Value>, String>> {
        Box::pin(async { Ok(None) })
    }
    fn list(&self) -> BoxFuture<'_, std::result::Result<Vec<String>, String>> {
        Box::pin(async { Ok(Vec::new()) })
    }
    fn write(&self, _: &str, _: Value) -> BoxFuture<'_, std::result::Result<(), String>> {
        Box::pin(async { Err("credentials are not stored here".into()) })
    }
    fn delete(&self, _: &str) -> BoxFuture<'_, std::result::Result<(), String>> {
        Box::pin(async { Ok(()) })
    }
}

/// One tool call, as pi makes it.
#[derive(Debug, Clone)]
pub struct ToolCall {
    pub session_id: String,
    pub id: String,
    pub name: String,
    pub args: Value,
}

/// What a tool answers: pi `TextContent`/`ImageContent` parts for the model,
/// and `details` kept with the result for a UI, never sent to the model.
#[derive(Debug, Clone, Default)]
pub struct ToolResult {
    pub content: Vec<Value>,
    pub details: Value,
    /// Asks the agent to stop after this batch of tool calls.
    pub terminate: bool,
}

impl ToolResult {
    pub fn text(text: impl Into<String>) -> Self {
        Self { content: vec![json!({ "type": "text", "text": text.into() })], ..Self::default() }
    }

    pub fn with_details(mut self, details: Value) -> Self {
        self.details = details;
        self
    }
}

/// A tool's description, as the model sees it.
#[derive(Debug, Clone)]
pub struct ToolDef {
    pub name: String,
    pub description: String,
    /// JSON Schema of the arguments.
    pub parameters: Value,
    pub label: Option<String>,
    /// Never run alongside other tool calls.
    pub sequential: bool,
}

impl ToolDef {
    fn to_json(&self) -> Value {
        let mut v = json!({ "name": self.name, "description": self.description, "parameters": self.parameters });
        if let Some(l) = &self.label {
            v["label"] = json!(l);
        }
        if self.sequential {
            v["executionMode"] = json!("sequential");
        }
        v
    }
}

/// Why a tool call no longer matters: the run was aborted.
#[derive(Clone, Default)]
pub struct Cancel(Arc<(AtomicBool, Notify)>);

impl Cancel {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn is_cancelled(&self) -> bool {
        self.0.0.load(Ordering::SeqCst)
    }

    pub fn cancel(&self) {
        self.0.0.store(true, Ordering::SeqCst);
        self.0.1.notify_waiters();
    }

    /// Resolves once cancelled.
    pub async fn cancelled(&self) {
        loop {
            let notified = self.0.1.notified();
            if self.is_cancelled() {
                return;
            }
            notified.await;
        }
    }
}

/// A tool the model may call. An `Err` is reported to the model as the
/// tool's failure.
pub trait Tool: Send + Sync {
    fn def(&self) -> ToolDef;
    fn execute(&self, call: ToolCall, cancel: Cancel) -> BoxFuture<'_, std::result::Result<ToolResult, String>>;
}

/// The answer to a tool call awaiting approval; a denial's reason is told to
/// the model.
#[derive(Debug, Clone)]
pub enum Approval {
    Allow,
    Deny(Option<String>),
}

/// Decides whether a tool call may run. The run waits for the answer.
pub trait Approver: Send + Sync {
    fn approve(&self, call: ToolCall) -> BoxFuture<'_, Approval>;
}

/// Where the runtime's own log lines go: level (`debug`, `info`, `warn`,
/// `error`) and message.
pub type Logger = Arc<dyn Fn(&str, &str) + Send + Sync>;

/// What a runtime is started with.
pub struct Config {
    /// Where chats are kept: a SQLite file each, created on first use.
    pub dir: std::path::PathBuf,
    pub credentials: Arc<dyn Credentials>,
    pub fetch: Arc<dyn Fetch>,
    pub logger: Option<Logger>,
}

/// One open session's host side.
struct SessionHost {
    tools: Mutex<HashMap<String, Arc<dyn Tool>>>,
    approver: Mutex<Option<Arc<dyn Approver>>>,
    events: mpsc::UnboundedSender<Value>,
}

struct Inner {
    engine: Mutex<Option<Arc<Engine>>>,
    config: Config,
    next_req: AtomicU64,
    pending: Mutex<HashMap<u64, oneshot::Sender<Result<Value>>>>,
    sessions: Mutex<HashMap<String, Arc<SessionHost>>>,
    /// Response bodies being streamed in, by stream id (the `fetch` call's id).
    bodies: Mutex<HashMap<u64, tokio::task::AbortHandle>>,
    /// Tool calls running, by `<session>/<call>`.
    tool_cancels: Mutex<HashMap<String, Cancel>>,
    /// Streamed completions, by stream id.
    completions: Mutex<HashMap<u64, mpsc::UnboundedSender<Value>>>,
    next_stream: AtomicU64,
    fatal: Mutex<Option<String>>,
}

/// pi-durable and pi-ai on QuickJS, answered by this process. One is
/// enough for a program: sessions share it. Dropping the last handle stops it.
#[derive(Clone)]
pub struct Runtime(Arc<Inner>);

impl Runtime {
    /// Starts the engine. Must be called inside a Tokio runtime.
    pub fn start(config: Config) -> Result<Self> {
        let (tx, rx) = mpsc::unbounded_channel::<Outbound>();
        let inner = Arc::new(Inner {
            engine: Mutex::new(None),
            config,
            next_req: AtomicU64::new(1),
            pending: Mutex::default(),
            sessions: Mutex::default(),
            bodies: Mutex::default(),
            tool_cancels: Mutex::default(),
            completions: Mutex::default(),
            next_stream: AtomicU64::new(1),
            fatal: Mutex::new(None),
        });
        let dir = inner.config.dir.clone();
        let engine = Engine::spawn(
            Arc::new(move |o| {
                let _ = tx.send(o);
            }),
            Some(dir),
        )
        .map_err(|e| Error(format!("starting the engine: {e}")))?;
        *inner.engine.lock().unwrap() = Some(Arc::new(engine));
        tokio::spawn(pump(Arc::downgrade(&inner), rx));
        Ok(Self(inner))
    }

    /// Asks `__fl.dispatch(method, payload)`, the protocol `js/src/main.js`
    /// describes. The typed calls below are this.
    pub async fn request(&self, method: &str, payload: Value) -> Result<Value> {
        request(&self.0, method, payload).await
    }

    /// Versions of what runs, and the APIs a custom provider may speak.
    pub async fn info(&self) -> Result<Value> {
        self.request("runtime.info", json!({})).await
    }

    /// Replaces the custom providers (`LlmCustomProvider` JSON).
    pub async fn set_custom_providers(&self, providers: Value) -> Result<()> {
        self.request("providers.setCustom", json!({ "providers": providers })).await.map(drop)
    }

    /// Every stored session, newest first: `{id, createdAt, modifiedAt}`.
    pub async fn sessions(&self) -> Result<Vec<Value>> {
        match self.request("sessions.list", json!({})).await? {
            Value::Array(v) => Ok(v),
            _ => Ok(Vec::new()),
        }
    }

    /// Deletes a stored session. It must not be open.
    pub async fn delete_session(&self, id: &str) -> Result<()> {
        self.request("sessions.delete", json!({ "sessionId": id })).await.map(drop)
    }

    /// The sessions where `needle` was said by the user or the model,
    /// ignoring case.
    pub async fn search(&self, needle: &str) -> Result<Vec<String>> {
        let dir = self.0.config.dir.clone();
        let needle = needle.to_string();
        tokio::task::spawn_blocking(move || crate::db::search(&dir, &needle))
            .await
            .map_err(|e| Error(e.to_string()))?
            .map_err(Error)
    }

    /// Closes the session `id` wherever its [`Session`] handle is: for a
    /// handle still shared when its owner is done with it.
    pub async fn close_session(&self, id: &str) -> Result<()> {
        let r = self.request("session.close", json!({ "sessionId": id })).await;
        self.0.sessions.lock().unwrap().remove(id);
        r.map(drop)
    }

    /// Opens the session `id`, creating it when there is none. `model` is an
    /// `LlmModelRef` (`{provider, id}` or a custom model with `api`,
    /// `baseUrl`). Without an approver, tools run unasked.
    ///
    /// The events of the session arrive on the receiver returned with it, in
    /// order and all of them: it is unbounded, so read it.
    pub async fn open_session(&self, open: OpenSession) -> Result<(Session, mpsc::UnboundedReceiver<Value>)> {
        let (tx, rx) = mpsc::unbounded_channel();
        let host = Arc::new(SessionHost {
            tools: Mutex::new(open.tools.iter().map(|t| (t.def().name, t.clone())).collect()),
            approver: Mutex::new(open.approver.clone()),
            events: tx,
        });
        {
            let mut sessions = self.0.sessions.lock().unwrap();
            if sessions.contains_key(&open.id) {
                return Err(Error(format!("Session is already open: {}", open.id)));
            }
            sessions.insert(open.id.clone(), host);
        }
        let payload = json!({
            "sessionId": open.id,
            "model": open.model,
            "systemPrompt": open.system_prompt,
            "tools": open.tools.iter().map(|t| t.def().to_json()).collect::<Vec<_>>(),
            "thinkingLevel": open.thinking_level.unwrap_or_else(|| "off".into()),
            "compaction": open.compaction.unwrap_or_else(|| json!({})),
            "approval": open.approver.is_some(),
        });
        match self.request("session.open", payload).await {
            Ok(v) => {
                let interrupted = v["interrupted"].as_array().is_some_and(|a| !a.is_empty());
                let name = v["name"].as_str().map(str::to_string);
                Ok((Session { rt: self.clone(), id: open.id, interrupted, name, closed: Arc::default() }, rx))
            }
            Err(e) => {
                self.0.sessions.lock().unwrap().remove(&open.id);
                Err(e)
            }
        }
    }

    /// One completion outside any session — a title, a summary. With
    /// `on_event`, pi's `AssistantMessageEvent`s arrive there as they stream.
    pub async fn complete(
        &self,
        model: Value,
        messages: Value,
        system_prompt: Option<String>,
        on_event: Option<mpsc::UnboundedSender<Value>>,
    ) -> Result<Value> {
        let stream_id = on_event.map(|tx| {
            let id = self.0.next_stream.fetch_add(1, Ordering::Relaxed);
            self.0.completions.lock().unwrap().insert(id, tx);
            id
        });
        let r = self
            .request("complete", json!({ "model": model, "messages": messages, "systemPrompt": system_prompt, "streamId": stream_id }))
            .await;
        if let Some(id) = stream_id {
            self.0.completions.lock().unwrap().remove(&id);
        }
        r
    }
}

/// What [`Runtime::open_session`] opens a session with. A reopened session
/// keeps its history, not its settings: these are what it runs with now.
pub struct OpenSession {
    pub id: String,
    pub model: Value,
    pub system_prompt: String,
    pub tools: Vec<Arc<dyn Tool>>,
    pub approver: Option<Arc<dyn Approver>>,
    /// `off` when `None`.
    pub thinking_level: Option<String>,
    /// pi's `CompactionSettings`, over its defaults.
    pub compaction: Option<Value>,
}

/// One conversation: a pi session, open in the runtime. An append-only tree
/// of entries; [`Session::entries`] is the current branch.
pub struct Session {
    rt: Runtime,
    id: String,
    interrupted: bool,
    name: Option<String>,
    closed: Arc<AtomicBool>,
}

impl Session {
    pub fn id(&self) -> &str {
        &self.id
    }

    /// Whether a run was left unfinished when it was last open (a crash, a
    /// restart). [`Session::resume`] picks it up.
    pub fn interrupted(&self) -> bool {
        self.interrupted
    }

    pub fn name(&self) -> Option<&str> {
        self.name.as_deref()
    }

    async fn call(&self, method: &str, mut payload: Value) -> Result<Value> {
        if self.closed.load(Ordering::SeqCst) {
            return Err(Error("Session closed".into()));
        }
        payload["sessionId"] = json!(self.id);
        self.rt.request(method, payload).await
    }

    /// Sends `text` and runs until the agent is done, tools included.
    /// `images` are pi `ImageContent` parts. Answers pi's run result.
    pub async fn prompt(&self, text: &str, images: Option<Value>) -> Result<Value> {
        Ok(self.call("session.prompt", json!({ "text": text, "images": images })).await?["result"].take())
    }

    /// Continues an interrupted run, or retries after an error.
    pub async fn resume(&mut self) -> Result<Value> {
        self.interrupted = false;
        Ok(self.call("session.resume", json!({})).await?["result"].take())
    }

    /// Stops the current run; [`Session::prompt`] then answers `aborted`.
    pub fn abort(&self) -> impl Future<Output = Result<()>> + Send + 'static {
        let (rt, id, closed) = (self.rt.clone(), self.id.clone(), self.closed.clone());
        async move {
            if closed.load(Ordering::SeqCst) {
                return Ok(());
            }
            rt.request("session.abort", json!({ "sessionId": id })).await.map(drop)
        }
    }

    /// The current branch, root first. Reads it all; see [`Session::page`].
    pub async fn entries(&self) -> Result<Vec<Value>> {
        entries(self.call("session.entries", json!({})).await?)
    }

    /// The last `limit` entries of the current branch before `before` (its
    /// end: `None`), root first, from a user message on; and whether there
    /// are more before them. A user message with more than one version
    /// carries them as `versions`.
    pub async fn page(&self, limit: usize, before: Option<&str>) -> Result<(Vec<Value>, bool)> {
        let mut v = self.call("session.page", json!({ "limit": limit, "before": before })).await?;
        let more = v["more"] == true;
        Ok((entries(v.take())?, more))
    }

    /// Every entry, on every branch. Reads them all.
    pub async fn tree(&self) -> Result<Vec<Value>> {
        entries(self.call("session.tree", json!({})).await?)
    }

    /// Moves the branch tip to `target_id` (`None`: before the first entry).
    /// The next prompt grows a new branch there.
    pub async fn navigate(&self, target_id: Option<&str>) -> Result<()> {
        self.call("session.navigate", json!({ "targetId": target_id })).await.map(drop)
    }

    /// Stands on the version `entry_id` starts: its newest leaf.
    pub async fn switch_to(&self, entry_id: &str) -> Result<()> {
        self.call("session.switchTo", json!({ "entryId": entry_id })).await.map(drop)
    }

    /// Appends an entry of the host's own kind, which the model never sees.
    pub async fn append_custom(&self, custom_type: &str, data: Value) -> Result<String> {
        let v = self.call("session.appendCustom", json!({ "customType": custom_type, "data": data })).await?;
        Ok(v["id"].as_str().unwrap_or_default().to_string())
    }

    /// Appends messages without running the model; answers their entry ids.
    pub async fn append(&self, messages: Value) -> Result<Vec<String>> {
        let v = self.call("session.append", json!({ "messages": messages })).await?;
        Ok(v["ids"].as_array().map(|a| a.iter().filter_map(|i| i.as_str().map(str::to_string)).collect()).unwrap_or_default())
    }

    pub async fn set_model(&self, model: Value) -> Result<()> {
        self.call("session.setModel", json!({ "model": model })).await.map(drop)
    }

    pub async fn set_system_prompt(&self, prompt: &str) -> Result<()> {
        self.call("session.setSystemPrompt", json!({ "systemPrompt": prompt })).await.map(drop)
    }

    pub async fn set_thinking_level(&self, level: &str) -> Result<()> {
        self.call("session.setThinkingLevel", json!({ "thinkingLevel": level })).await.map(drop)
    }

    pub async fn set_tools(&self, tools: Vec<Arc<dyn Tool>>) -> Result<()> {
        let defs: Vec<Value> = tools.iter().map(|t| t.def().to_json()).collect();
        if let Some(h) = self.rt.0.sessions.lock().unwrap().get(&self.id) {
            *h.tools.lock().unwrap() = tools.iter().map(|t| (t.def().name, t.clone())).collect();
        }
        self.call("session.setTools", json!({ "tools": defs })).await.map(drop)
    }

    pub async fn set_approver(&self, approver: Option<Arc<dyn Approver>>) -> Result<()> {
        let on = approver.is_some();
        if let Some(h) = self.rt.0.sessions.lock().unwrap().get(&self.id) {
            *h.approver.lock().unwrap() = approver;
        }
        self.call("session.setApproval", json!({ "approval": on })).await.map(drop)
    }

    pub async fn set_name(&mut self, name: Option<&str>) -> Result<()> {
        self.call("session.setName", json!({ "name": name })).await?;
        self.name = name.map(str::to_string);
        Ok(())
    }

    /// The session as a file pi's coding agent reads (session format v3),
    /// recorded as made in `cwd`: every version, the current one last, which
    /// is where `pi` continues.
    pub async fn export_pi(&self, cwd: &str) -> Result<String> {
        let v = self.call("session.exportPi", json!({ "cwd": cwd })).await?;
        Ok(v["text"].as_str().unwrap_or_default().to_string())
    }

    /// Compacts now, whatever the thresholds say. Answers how it went:
    /// `{status: completed | declined | aborted | failed, ...}`.
    pub async fn compact(&self, instructions: Option<&str>) -> Result<Value> {
        let mut v = self.call("session.compact", json!({ "customInstructions": instructions })).await?;
        Ok(v["compaction"].take())
    }

    /// Closes the session; it stays stored.
    pub async fn close(self) -> Result<()> {
        if self.closed.swap(true, Ordering::SeqCst) {
            return Ok(());
        }
        let r = self.rt.request("session.close", json!({ "sessionId": self.id })).await;
        self.rt.0.sessions.lock().unwrap().remove(&self.id);
        r.map(drop)
    }
}

fn entries(mut v: Value) -> Result<Vec<Value>> {
    match v["entries"].take() {
        Value::Array(a) => Ok(a),
        _ => Ok(Vec::new()),
    }
}

async fn request(inner: &Arc<Inner>, method: &str, payload: Value) -> Result<Value> {
    if let Some(f) = inner.fatal.lock().unwrap().clone() {
        return Err(Error(f));
    }
    let id = inner.next_req.fetch_add(1, Ordering::Relaxed);
    let (tx, rx) = oneshot::channel();
    inner.pending.lock().unwrap().insert(id, tx);
    let sent = engine(inner).is_some_and(|e| e.send(Inbound::Request { req_id: id, method: method.into(), payload: payload.to_string() }));
    if !sent {
        inner.pending.lock().unwrap().remove(&id);
        return Err(Error("Runtime stopped".into()));
    }
    rx.await.unwrap_or_else(|_| Err(Error("Runtime stopped".into())))
}

fn engine(inner: &Inner) -> Option<Arc<Engine>> {
    inner.engine.lock().unwrap().clone()
}

impl Drop for Inner {
    fn drop(&mut self) {
        for (_, b) in self.bodies.lock().unwrap().drain() {
            b.abort();
        }
        // The engine thread is joined here; nothing else holds it but a
        // body task, aborted above.
        self.engine.lock().unwrap().take();
    }
}

/// Answers what the engine says, until it is gone.
async fn pump(weak: Weak<Inner>, mut rx: mpsc::UnboundedReceiver<Outbound>) {
    while let Some(o) = rx.recv().await {
        let Some(inner) = weak.upgrade() else { return };
        match o {
            Outbound::Result { req_id, payload } => {
                let Some(tx) = inner.pending.lock().unwrap().remove(&req_id) else { continue };
                let v: Value = serde_json::from_str(&payload).unwrap_or(Value::Null);
                let r = if v["ok"] == true {
                    Ok(v.get("value").cloned().unwrap_or(Value::Null))
                } else {
                    Err(Error(v["error"].as_str().unwrap_or("Unknown error").to_string()))
                };
                let _ = tx.send(r);
            }
            Outbound::HostCall { call_id, name, payload, body } => {
                let inner = inner.clone();
                tokio::spawn(async move {
                    let answer = host_call(&inner, call_id, &name, &payload, body).await;
                    if let Some(e) = engine(&inner) {
                        e.send(Inbound::Answer { call_id, result: answer.map(|v| v.to_string()) });
                    }
                });
            }
            Outbound::Notify { name, payload } => notify(&inner, &name, &payload),
            Outbound::Event { payload } => {
                let Ok(mut e) = serde_json::from_str::<Value>(&payload) else { continue };
                match e["type"].as_str() {
                    Some("session.event") => {
                        let id = e["sessionId"].as_str().unwrap_or_default().to_string();
                        let host = inner.sessions.lock().unwrap().get(&id).cloned();
                        if let Some(h) = host {
                            let _ = h.events.send(e["event"].take());
                        }
                    }
                    Some("complete.event") => {
                        let id = e["streamId"].as_u64().unwrap_or_default();
                        if let Some(tx) = inner.completions.lock().unwrap().get(&id) {
                            let _ = tx.send(e["event"].take());
                        }
                    }
                    _ => {}
                }
            }
            Outbound::Log { level, message } => {
                if let Some(log) = &inner.config.logger {
                    log(&level, &message);
                }
            }
            Outbound::Fatal { message } => {
                if let Some(log) = &inner.config.logger {
                    log("error", &format!("fl_pi_llm runtime stopped: {message}"));
                }
                *inner.fatal.lock().unwrap() = Some(message.clone());
                for (_, tx) in inner.pending.lock().unwrap().drain() {
                    let _ = tx.send(Err(Error(message.clone())));
                }
            }
        }
    }
}

fn notify(inner: &Inner, name: &str, payload: &str) {
    let p: Value = serde_json::from_str(payload).unwrap_or(Value::Null);
    match name {
        "fetch.cancel" => {
            let id = p["streamId"].as_u64().unwrap_or_default();
            if let Some(b) = inner.bodies.lock().unwrap().remove(&id) {
                b.abort();
                // The body never ends on its own now, and a `read` may wait.
                if let Some(e) = engine(inner) {
                    e.send(Inbound::BodyEnd { stream_id: id, error: Some("aborted".into()) });
                }
            }
        }
        "tool.cancel" => {
            let key = format!("{}/{}", p["sessionId"].as_str().unwrap_or_default(), p["toolCallId"].as_str().unwrap_or_default());
            if let Some(c) = inner.tool_cancels.lock().unwrap().remove(&key) {
                c.cancel();
            }
        }
        _ => {}
    }
}

async fn host_call(inner: &Arc<Inner>, call_id: u64, name: &str, payload: &str, body: Option<Vec<u8>>) -> std::result::Result<Value, String> {
    let p: Value = serde_json::from_str(payload).map_err(|e| e.to_string())?;
    match name {
        "fetch" => fetch(inner, call_id, p, body).await,
        "tool" => Ok(run_tool(inner, p).await),
        "approve" => Ok(approve(inner, p).await),
        n if n.starts_with("auth.") => auth(&*inner.config.credentials, n, p).await,
        // A key from the environment is how pi-ai finds one under Node. A
        // Rust host hands keys over through its credentials, never its
        // environment, which would reach every provider asking for it.
        "env.get" => Ok(Value::Null),
        // Sessions from before pi-durable were the apps'; a Rust host has
        // none to move. TODO: remove with `js/src/legacy.js`.
        "legacy.list" => Ok(json!({ "files": [] })),
        other => Err(format!("Unknown host call: {other}")),
    }
}

async fn fetch(inner: &Arc<Inner>, call_id: u64, p: Value, body: Option<Vec<u8>>) -> std::result::Result<Value, String> {
    let headers = p["headers"]
        .as_object()
        .map(|h| h.iter().map(|(k, v)| (k.clone(), v.as_str().map_or_else(|| v.to_string(), str::to_string))).collect())
        .unwrap_or_default();
    let req = FetchRequest {
        url: p["url"].as_str().unwrap_or_default().to_string(),
        method: p["method"].as_str().unwrap_or("GET").to_string(),
        headers,
        body,
    };
    let mut res = inner.config.fetch.fetch(req).await?;
    let head = json!({
        "status": res.status,
        "statusText": res.status_text,
        "headers": res.headers.iter().map(|(k, v)| (k.clone(), json!(v))).collect::<serde_json::Map<_, _>>(),
        "streamId": call_id,
    });
    let weak = Arc::downgrade(inner);
    let task = tokio::spawn(async move {
        let mut error = None;
        while let Some(chunk) = res.body.recv().await {
            let Some(inner) = weak.upgrade() else { return };
            match chunk {
                Ok(c) => {
                    if let Some(e) = engine(&inner) {
                        e.send(Inbound::BodyChunk { stream_id: call_id, chunk: c });
                    }
                }
                Err(e) => {
                    error = Some(e);
                    break;
                }
            }
        }
        if let Some(inner) = weak.upgrade() {
            inner.bodies.lock().unwrap().remove(&call_id);
            if let Some(e) = engine(&inner) {
                e.send(Inbound::BodyEnd { stream_id: call_id, error });
            }
        }
    });
    inner.bodies.lock().unwrap().insert(call_id, task.abort_handle());
    if task.is_finished() {
        inner.bodies.lock().unwrap().remove(&call_id);
    }
    Ok(head)
}

async fn run_tool(inner: &Arc<Inner>, p: Value) -> Value {
    let session_id = p["sessionId"].as_str().unwrap_or_default().to_string();
    let name = p["name"].as_str().unwrap_or_default().to_string();
    let tool = inner.sessions.lock().unwrap().get(&session_id).and_then(|h| h.tools.lock().unwrap().get(&name).cloned());
    let Some(tool) = tool else { return json!({ "error": format!("Unknown tool: {name}") }) };
    let call_id = p["toolCallId"].as_str().unwrap_or_default().to_string();
    let key = format!("{session_id}/{call_id}");
    let cancel = Cancel::new();
    inner.tool_cancels.lock().unwrap().insert(key.clone(), cancel.clone());
    let call = ToolCall { session_id, id: call_id, name, args: p["args"].clone() };
    let r = tool.execute(call, cancel).await;
    inner.tool_cancels.lock().unwrap().remove(&key);
    match r {
        Ok(r) => {
            let mut v = json!({ "content": r.content, "details": r.details });
            if r.terminate {
                v["terminate"] = json!(true);
            }
            v
        }
        Err(e) => json!({ "error": e }),
    }
}

async fn approve(inner: &Arc<Inner>, p: Value) -> Value {
    let session_id = p["sessionId"].as_str().unwrap_or_default().to_string();
    let approver = inner.sessions.lock().unwrap().get(&session_id).and_then(|h| h.approver.lock().unwrap().clone());
    let Some(approver) = approver else { return json!({ "block": false }) };
    let call = ToolCall {
        session_id,
        id: p["toolCallId"].as_str().unwrap_or_default().to_string(),
        name: p["name"].as_str().unwrap_or_default().to_string(),
        args: p["args"].clone(),
    };
    match approver.approve(call).await {
        Approval::Allow => json!({ "block": false }),
        Approval::Deny(reason) => json!({ "block": true, "reason": reason }),
    }
}

async fn auth(c: &dyn Credentials, op: &str, p: Value) -> std::result::Result<Value, String> {
    let id = p["providerId"].as_str().unwrap_or_default();
    Ok(match op {
        "auth.read" => c.read(id).await?.unwrap_or(Value::Null),
        "auth.list" => json!(c.list().await?.into_iter().map(|id| json!({ "providerId": id, "type": "api_key" })).collect::<Vec<_>>()),
        "auth.write" => {
            c.write(id, p["credential"].clone()).await?;
            Value::Null
        }
        "auth.delete" => {
            c.delete(id).await?;
            Value::Null
        }
        other => return Err(format!("Unknown auth call: {other}")),
    })
}
