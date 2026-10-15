//! MCP servers' tools for a Rust host: a client of the Streamable HTTP
//! transport (MCP 2025-06-18), its requests made through the host's
//! [`Fetch`], and each tool a server lists as a [`Tool`] the model may call.
//!
//! What a tool is called, and what its answer becomes, is [`crate::mcp`],
//! which the apps use too, so a session reads the same in both.
//!
//! Only what a host that holds a token needs: headers sent with every
//! request (`Authorization: Bearer …`). Signing in through a browser (OAuth)
//! is the app's.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::{Value, json};
use tokio::sync::mpsc;

use super::{BoxFuture, Cancel, Fetch, FetchRequest, Tool, ToolCall, ToolDef, ToolResult};
pub use crate::mcp::{McpTool, server_id, tool_name};
use crate::mcp::{call_result, server_instructions, server_name};

/// The protocol version asked for; the server answers the one it speaks.
pub const PROTOCOL_VERSION: &str = "2025-06-18";
/// A request's answer, at most: a tool may run long (a backup, a scan).
const CALL_TIMEOUT: Duration = Duration::from_secs(5 * 60);
const LIST_TIMEOUT: Duration = Duration::from_secs(30);
/// What one answer may be, read off the wire.
const MAX_BODY: usize = 16 << 20;
/// Tools listed of one server, at most: pages are followed this far.
const MAX_TOOLS: usize = 256;

/// One MCP server: where it is, and the headers sent with each request.
#[derive(Debug, Clone)]
pub struct McpServerConfig {
    pub url: String,
    pub headers: Vec<(String, String)>,
}

/// A connected server.
pub struct McpClient {
    fetch: Arc<dyn Fetch>,
    config: McpServerConfig,
    next_id: AtomicU64,
    session: Mutex<Session>,
    /// What the server calls itself; its host until it has said.
    pub name: String,
    /// What it says about using it, for the system prompt.
    pub instructions: Option<String>,
}

#[derive(Default, Clone)]
struct Session {
    id: Option<String>,
    version: Option<String>,
}

/// An answer that is not the one asked for: why, for the caller to say.
#[derive(Debug)]
enum Failure {
    /// The session the server knew is gone (404 with a session id): connect
    /// again and ask again.
    SessionGone,
    Other(String),
}

impl From<String> for Failure {
    fn from(s: String) -> Self {
        Failure::Other(s)
    }
}

impl McpClient {
    /// Connects to [config]: `initialize`, then `notifications/initialized`.
    pub async fn connect(fetch: Arc<dyn Fetch>, config: McpServerConfig) -> Result<Self, String> {
        let mut client = Self {
            fetch,
            name: crate::mcp::host_of(&config.url),
            config,
            next_id: AtomicU64::new(1),
            session: Mutex::new(Session::default()),
            instructions: None,
        };
        let info = client.initialize().await?;
        client.name = server_name(&info, &client.config.url);
        client.instructions = server_instructions(info["instructions"].as_str());
        Ok(client)
    }

    pub fn url(&self) -> &str {
        &self.config.url
    }

    /// A new session: what the server said of itself.
    async fn initialize(&self) -> Result<Value, String> {
        *self.session.lock().unwrap() = Session::default();
        let params = json!({
            "protocolVersion": PROTOCOL_VERSION,
            "capabilities": {},
            "clientInfo": { "name": "fl_pi_llm", "version": env!("CARGO_PKG_VERSION") },
        });
        let info = self.exchange("initialize", params, LIST_TIMEOUT, &Cancel::new()).await.map_err(|f| match f {
            Failure::SessionGone => "the server dropped the session while starting it".to_string(),
            Failure::Other(e) => e,
        })?;
        let version = info["protocolVersion"].as_str().unwrap_or(PROTOCOL_VERSION).to_string();
        self.session.lock().unwrap().version = Some(version);
        self.post(json!({ "jsonrpc": "2.0", "method": "notifications/initialized" }), None).await.map_err(|f| match f {
            Failure::SessionGone => "the server dropped the session while starting it".to_string(),
            Failure::Other(e) => e,
        })?;
        Ok(info)
    }

    /// Every tool the server lists, its pages followed.
    pub async fn list_tools(&self) -> Result<Vec<McpTool>, String> {
        let mut tools = Vec::new();
        let mut cursor: Option<String> = None;
        loop {
            let params = match &cursor {
                Some(c) => json!({ "cursor": c }),
                None => json!({}),
            };
            let page = self.request("tools/list", params, LIST_TIMEOUT, &Cancel::new()).await?;
            tools.extend(page["tools"].as_array().into_iter().flatten().filter_map(McpTool::from_json));
            cursor = page["nextCursor"].as_str().filter(|c| !c.is_empty()).map(String::from);
            if cursor.is_none() || tools.len() >= MAX_TOOLS {
                tools.truncate(MAX_TOOLS);
                return Ok(tools);
            }
        }
    }

    /// Calls [tool] with [args]: its answer as pi content, or why it failed
    /// (the server's error, or the tool's own `isError` text).
    pub async fn call(&self, tool: &str, args: Value, cancel: &Cancel) -> Result<ToolResult, String> {
        let args = if args.is_object() { args } else { json!({}) };
        let res = self.request("tools/call", json!({ "name": tool, "arguments": args }), CALL_TIMEOUT, cancel).await?;
        let (content, details) = call_result(tool, &res)?;
        Ok(ToolResult { content, details, terminate: false })
    }

    /// A request, its session started again once when the server forgot it.
    async fn request(&self, method: &str, params: Value, timeout: Duration, cancel: &Cancel) -> Result<Value, String> {
        match self.exchange(method, params.clone(), timeout, cancel).await {
            Err(Failure::SessionGone) => {
                self.initialize().await?;
                self.exchange(method, params, timeout, cancel).await.map_err(|f| match f {
                    Failure::SessionGone => "the server dropped the session again".to_string(),
                    Failure::Other(e) => e,
                })
            }
            Err(Failure::Other(e)) => Err(e),
            Ok(v) => Ok(v),
        }
    }

    /// One JSON-RPC request and its answer's `result`.
    async fn exchange(&self, method: &str, params: Value, timeout: Duration, cancel: &Cancel) -> Result<Value, Failure> {
        let id = self.next_id.fetch_add(1, Ordering::Relaxed);
        let body = json!({ "jsonrpc": "2.0", "id": id, "method": method, "params": params });
        let answer = tokio::select! {
            r = tokio::time::timeout(timeout, self.post(body, Some(id))) => match r {
                Ok(r) => r,
                Err(_) => {
                    self.cancelled(id, "timed out").await;
                    return Err(Failure::Other(format!("{method}: no answer in {}s", timeout.as_secs())));
                }
            },
            _ = cancel.cancelled() => {
                self.cancelled(id, "stopped by the user").await;
                return Err(Failure::Other("stopped".into()));
            }
        }?;
        let Some(answer) = answer else { return Err(Failure::Other(format!("{method}: the server answered nothing"))) };
        if let Some(e) = answer.get("error") {
            let message = e["message"].as_str().unwrap_or("error");
            return Err(Failure::Other(format!("{method}: {message} ({})", e["code"])));
        }
        Ok(answer.get("result").cloned().unwrap_or(Value::Null))
    }

    /// Tells the server request [id] is no longer wanted.
    async fn cancelled(&self, id: u64, reason: &str) {
        let note = json!({ "jsonrpc": "2.0", "method": "notifications/cancelled", "params": { "requestId": id, "reason": reason } });
        let _ = tokio::time::timeout(Duration::from_secs(5), self.post(note, None)).await;
    }

    /// POSTs [message]; for a request ([id]), its answer, read from a JSON
    /// body or from the event stream the server opened for it.
    async fn post(&self, message: Value, id: Option<u64>) -> Result<Option<Value>, Failure> {
        let session = self.session.lock().unwrap().clone();
        let mut headers = vec![
            ("content-type".to_string(), "application/json".to_string()),
            ("accept".to_string(), "application/json, text/event-stream".to_string()),
        ];
        if let Some(v) = &session.version {
            headers.push(("mcp-protocol-version".into(), v.clone()));
        }
        if let Some(s) = &session.id {
            headers.push(("mcp-session-id".into(), s.clone()));
        }
        headers.extend(self.config.headers.iter().cloned());
        let req = FetchRequest { url: self.config.url.clone(), method: "POST".into(), headers, body: Some(message.to_string().into_bytes()) };
        let mut res = self.fetch.fetch(req).await?;
        let header = |name: &str| res.headers.iter().find(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v.clone());
        if let Some(s) = header("mcp-session-id") {
            self.session.lock().unwrap().id = Some(s);
        }
        let content_type = header("content-type").unwrap_or_default().to_ascii_lowercase();
        if res.status == 404 && session.id.is_some() {
            return Err(Failure::SessionGone);
        }
        if !(200..300).contains(&res.status) {
            let body = read_all(&mut res.body).await.unwrap_or_default();
            let text = String::from_utf8_lossy(&body);
            return Err(Failure::Other(format!("HTTP {} {}", res.status, crate::mcp::cap(text.trim(), 300))));
        }
        let Some(id) = id else { return Ok(None) };
        if content_type.starts_with("text/event-stream") {
            return answer_from_events(&mut res.body, id).await.map(Some).map_err(Failure::Other);
        }
        let body = read_all(&mut res.body).await?;
        let value: Value = serde_json::from_slice(&body).map_err(|e| format!("not JSON-RPC: {e}"))?;
        // A batch is allowed by older versions of the protocol.
        let found = match value {
            Value::Array(items) => items.into_iter().find(|v| v["id"].as_u64() == Some(id)),
            v => Some(v),
        };
        found.map(Some).ok_or_else(|| Failure::Other("no answer to the request".into()))
    }
}

async fn read_all(body: &mut mpsc::Receiver<Result<Vec<u8>, String>>) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    while let Some(chunk) = body.recv().await {
        out.extend(chunk?);
        if out.len() > MAX_BODY {
            return Err("the answer is too large".into());
        }
    }
    Ok(out)
}

/// The JSON-RPC answer to [id] among a server-sent event stream's messages;
/// the rest (notifications, the server's own requests) is passed over.
async fn answer_from_events(body: &mut mpsc::Receiver<Result<Vec<u8>, String>>, id: u64) -> Result<Value, String> {
    let mut buf = String::new();
    let mut pending = Vec::new();
    let mut read = 0usize;
    loop {
        // Every complete event in what has arrived.
        while let Some((event, rest)) = split_event(&buf) {
            let data: Vec<&str> =
                event.lines().filter_map(|l| l.strip_prefix("data:")).map(|d| d.strip_prefix(' ').unwrap_or(d)).collect();
            let rest = rest.to_string();
            if !data.is_empty()
                && let Ok(message) = serde_json::from_str::<Value>(&data.join("\n"))
                && message["id"].as_u64() == Some(id)
                && (message.get("result").is_some() || message.get("error").is_some())
            {
                return Ok(message);
            }
            buf = rest;
        }
        match body.recv().await {
            Some(chunk) => {
                let chunk = chunk?;
                read += chunk.len();
                if read > MAX_BODY {
                    return Err("the answer is too large".into());
                }
                pending.extend(chunk);
                // Only whole characters: a chunk may end inside one.
                let valid = match std::str::from_utf8(&pending) {
                    Ok(s) => s.len(),
                    Err(e) => e.valid_up_to(),
                };
                buf.push_str(std::str::from_utf8(&pending[..valid]).unwrap_or_default());
                pending.drain(..valid);
                buf = buf.replace("\r\n", "\n");
            }
            None => return Err("the server closed the stream before answering".into()),
        }
    }
}

fn split_event(buf: &str) -> Option<(&str, &str)> {
    buf.find("\n\n").map(|at| (&buf[..at], &buf[at + 2..]))
}

/// One tool of a connected server, as the model calls it.
pub struct McpToolHandle {
    pub client: Arc<McpClient>,
    pub server_id: String,
    pub tool: McpTool,
}

impl McpToolHandle {
    /// Every tool of [client], ready to give a session.
    pub fn all(client: Arc<McpClient>, tools: Vec<McpTool>) -> Vec<Self> {
        let id = server_id(client.url());
        tools.into_iter().map(|tool| Self { client: client.clone(), server_id: id.clone(), tool }).collect()
    }

    /// `server · tool`, as a person reads it.
    pub fn label(&self) -> String {
        self.tool.label_for(&self.client.name)
    }
}

impl Tool for McpToolHandle {
    fn def(&self) -> ToolDef {
        ToolDef {
            name: tool_name(&self.server_id, &self.tool.name),
            description: self.tool.description_for(&self.client.name),
            parameters: self.tool.input_schema.clone(),
            label: Some(self.label()),
            sequential: false,
        }
    }

    fn execute(&self, call: ToolCall, cancel: Cancel) -> BoxFuture<'_, Result<ToolResult, String>> {
        Box::pin(async move { self.client.call(&self.tool.name, call.args, &cancel).await })
    }
}

/// What connected servers say about using them, for the system prompt; None
/// when none says anything.
pub fn instructions(clients: &[Arc<McpClient>]) -> Option<String> {
    let servers: Vec<(String, String)> = clients.iter().filter_map(|c| Some((c.name.clone(), c.instructions.clone()?))).collect();
    crate::mcp::instructions(&servers)
}

#[cfg(test)]
mod tests {
    use super::super::FetchResponse;
    use super::*;

    /// A request as the fake saw it: its headers and its body.
    type Seen = (Vec<(String, String)>, Value);

    /// An MCP server in memory: answers JSON or an event stream, keeps a
    /// session, and forgets it once when told to.
    struct Fake {
        seen: Mutex<Vec<Seen>>,
        events: bool,
        forget_once: Mutex<bool>,
    }

    impl Fake {
        fn new(events: bool) -> Arc<Self> {
            Arc::new(Self { seen: Mutex::default(), events, forget_once: Mutex::new(false) })
        }

        fn answer(&self, msg: &Value) -> Option<Value> {
            let id = msg.get("id")?.clone();
            let result = match msg["method"].as_str()? {
                "initialize" => json!({
                    "protocolVersion": "2025-03-26",
                    "capabilities": { "tools": {} },
                    "serverInfo": { "name": "fake", "title": "Fake Home" },
                    "instructions": "Use list_lights first.",
                }),
                "tools/list" if msg["params"]["cursor"].is_null() => json!({
                    "tools": [{ "name": "list_lights", "description": "Lists lights", "inputSchema": { "type": "object" }, "annotations": { "readOnlyHint": true } }],
                    "nextCursor": "p2",
                }),
                "tools/list" => json!({ "tools": [{ "name": "turn.on", "inputSchema": { "type": "object", "properties": { "id": { "type": "string" } } } }] }),
                "tools/call" if msg["params"]["name"] == "broken" => json!({ "content": [{ "type": "text", "text": "no such light" }], "isError": true }),
                "tools/call" => json!({
                    "content": [
                        { "type": "text", "text": format!("on: {}", msg["params"]["arguments"]["id"]) },
                        { "type": "image", "data": "AAAA", "mimeType": "image/png" },
                        { "type": "resource", "resource": { "uri": "file:///a.txt", "text": "A" } },
                    ],
                    "structuredContent": { "ok": true },
                }),
                _ => return Some(json!({ "jsonrpc": "2.0", "id": id, "error": { "code": -32601, "message": "unknown" } })),
            };
            Some(json!({ "jsonrpc": "2.0", "id": id, "result": result }))
        }
    }

    impl Fetch for Fake {
        fn fetch(&self, req: FetchRequest) -> BoxFuture<'_, Result<FetchResponse, String>> {
            Box::pin(async move {
                let msg: Value = serde_json::from_slice(req.body.as_deref().unwrap_or_default()).unwrap();
                self.seen.lock().unwrap().push((req.headers.clone(), msg.clone()));
                let has_session = req.headers.iter().any(|(k, v)| k == "mcp-session-id" && v == "s1");
                let (tx, rx) = mpsc::channel(4);
                let mut headers = vec![];
                let status = if msg["method"] == "initialize" {
                    headers.push(("mcp-session-id".to_string(), "s1".to_string()));
                    200
                } else if !has_session || std::mem::take(&mut *self.forget_once.lock().unwrap()) {
                    404
                } else if msg.get("id").is_none() {
                    202
                } else {
                    200
                };
                if status == 200 {
                    let answer = self.answer(&msg).unwrap();
                    if self.events {
                        headers.push(("content-type".into(), "text/event-stream".into()));
                        // A notification first, then the answer split across chunks.
                        let text = format!(
                            "event: message\r\ndata: {}\r\n\r\ndata: {}\r\n\r\n",
                            json!({ "jsonrpc": "2.0", "method": "notifications/progress", "params": {} }),
                            answer
                        );
                        let (a, b) = text.split_at(text.len() / 2);
                        tx.send(Ok(a.as_bytes().to_vec())).await.unwrap();
                        tx.send(Ok(b.as_bytes().to_vec())).await.unwrap();
                    } else {
                        headers.push(("content-type".into(), "application/json".into()));
                        tx.send(Ok(answer.to_string().into_bytes())).await.unwrap();
                    }
                }
                Ok(FetchResponse { status, status_text: String::new(), headers, body: rx })
            })
        }
    }

    fn config() -> McpServerConfig {
        McpServerConfig { url: "https://home.test/api/mcp".into(), headers: vec![("authorization".into(), "Bearer t".into())] }
    }

    async fn check(events: bool) {
        let fake = Fake::new(events);
        let client = Arc::new(McpClient::connect(fake.clone(), config()).await.unwrap());
        assert_eq!(client.name, "Fake Home");
        assert_eq!(client.instructions.as_deref(), Some("Use list_lights first."));
        let tools = client.list_tools().await.unwrap();
        assert_eq!(tools.iter().map(|t| t.name.as_str()).collect::<Vec<_>>(), ["list_lights", "turn.on"]);
        assert!(tools[0].read_only && !tools[0].destructive);
        assert!(!tools[1].read_only && tools[1].destructive, "not said otherwise: may destroy");

        let handles = McpToolHandle::all(client.clone(), tools);
        let def = handles[1].def();
        assert_eq!(def.name, format!("{}__turn_on", server_id("https://home.test/api/mcp")));
        assert_eq!(def.description, "[Fake Home]");
        assert_eq!(def.label.as_deref(), Some("Fake Home · turn.on"));
        let call = ToolCall { session_id: "s".into(), id: "c".into(), name: def.name, args: json!({ "id": "hall" }) };
        let res = handles[1].execute(call, Cancel::new()).await.unwrap();
        assert_eq!(res.content[0]["text"], "on: \"hall\"");
        assert_eq!(res.content[1], json!({ "type": "image", "data": "AAAA", "mimeType": "image/png" }));
        assert_eq!(res.content[2]["text"], "[file:///a.txt]\nA");
        assert_eq!(res.details, json!({ "ok": true }));
        assert_eq!(client.call("broken", json!({}), &Cancel::new()).await.unwrap_err(), "no such light");

        // Every request after the first carries the session, the version the
        // server chose and the configured headers.
        let seen = fake.seen.lock().unwrap();
        assert_eq!(seen[1].1["method"], "notifications/initialized");
        for (headers, _) in seen.iter().skip(1) {
            let has = |k: &str, v: &str| headers.iter().any(|(hk, hv)| hk == k && hv == v);
            assert!(has("mcp-session-id", "s1") && has("mcp-protocol-version", "2025-03-26") && has("authorization", "Bearer t"));
        }
    }

    #[tokio::test]
    async fn json_answers() {
        check(false).await;
    }

    #[tokio::test]
    async fn event_stream_answers() {
        check(true).await;
    }

    #[tokio::test]
    async fn a_forgotten_session_is_started_again() {
        let fake = Fake::new(false);
        let client = McpClient::connect(fake.clone(), config()).await.unwrap();
        *fake.forget_once.lock().unwrap() = true;
        assert_eq!(client.list_tools().await.unwrap().len(), 2);
        let methods: Vec<String> = fake.seen.lock().unwrap().iter().map(|(_, m)| m["method"].as_str().unwrap().to_string()).collect();
        assert_eq!(methods[2..5], ["tools/list", "initialize", "notifications/initialized"]);
    }
}
