//! The whole path, minus Dart: the bundle on QuickJS, host calls answered by a
//! test host that does real HTTP against a mock OpenAI-compatible server.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::mpsc::{self, Receiver};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use fl_pi_llm::engine::{Engine, Inbound, Outbound};
use serde_json::{json, Value};

/// An OpenAI chat-completions server that streams. The first request gets a
/// tool call; any request carrying a tool result gets text, one word per chunk.
fn mock_server(delay: Duration) -> (String, Arc<Mutex<Vec<Value>>>) {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let addr = listener.local_addr().unwrap();
    let seen = Arc::new(Mutex::new(Vec::new()));
    let seen2 = seen.clone();
    thread::spawn(move || {
        for conn in listener.incoming() {
            let Ok(mut conn) = conn else { continue };
            let seen = seen2.clone();
            thread::spawn(move || {
                let mut reader = BufReader::new(conn.try_clone().unwrap());
                let mut len = 0usize;
                loop {
                    let mut line = String::new();
                    if reader.read_line(&mut line).unwrap() == 0 { return; }
                    let l = line.trim_end();
                    if l.is_empty() { break; }
                    if let Some(v) = l.to_ascii_lowercase().strip_prefix("content-length:") {
                        len = v.trim().parse().unwrap();
                    }
                }
                let mut body = vec![0u8; len];
                reader.read_exact(&mut body).unwrap();
                let req: Value = serde_json::from_slice(&body).unwrap();
                seen.lock().unwrap().push(req.clone());
                let has_tool = req["messages"].as_array().unwrap().iter().any(|m| m["role"] == "tool");
                let is_summary = req["messages"].as_array().unwrap().iter()
                    .any(|m| m["content"].to_string().contains("<conversation>"));
                write!(conn, "HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\nconnection: close\r\n\r\n").unwrap();
                let base = json!({"id":"c1","object":"chat.completion.chunk","created":1,"model":req["model"]});
                let mut send = |delta: Value, finish: Option<&str>| {
                    let mut c = base.clone();
                    c["choices"] = json!([{"index":0,"delta":delta,"finish_reason":finish}]);
                    if finish.is_some() {
                        c["usage"] = json!({"prompt_tokens":10,"completion_tokens":5,"total_tokens":15});
                    }
                    let _ = write!(conn, "data: {c}\n\n");
                    let _ = conn.flush();
                };
                let tools_offered = req.get("tools").is_some();
                if is_summary {
                    send(json!({"role":"assistant","content":"SUMMARY"}), None);
                    send(json!({}), Some("stop"));
                } else if !has_tool && tools_offered {
                    send(json!({"role":"assistant","tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"get_time","arguments":""}}]}), None);
                    thread::sleep(delay);
                    send(json!({"tool_calls":[{"index":0,"function":{"arguments":"{\"tz\":\"UTC\"}"}}]}), None);
                    send(json!({}), Some("tool_calls"));
                } else {
                    for w in ["It ", "is ", "12:00", "."] {
                        send(json!({"content": w}), None);
                        thread::sleep(delay);
                    }
                    send(json!({}), Some("stop"));
                }
                let _ = write!(conn, "data: [DONE]\n\n");
            });
        }
    });
    (format!("http://{addr}/v1"), seen)
}

/// Performs a `fetch` host call with a plain socket, streaming the body back.
fn do_fetch(engine: Arc<Engine>, call_id: u64, payload: &str, body: Option<Vec<u8>>) {
    let req: Value = serde_json::from_str(payload).unwrap();
    let url = req["url"].as_str().unwrap().to_string();
    let rest = url.strip_prefix("http://").unwrap();
    let (hostport, path) = rest.split_once('/').unwrap();
    let mut s = TcpStream::connect(hostport).unwrap();
    let body = body.unwrap_or_default();
    write!(s, "{} /{} HTTP/1.1\r\nhost: {}\r\ncontent-length: {}\r\n", req["method"].as_str().unwrap(), path, hostport, body.len()).unwrap();
    for (k, v) in req["headers"].as_object().unwrap() {
        if k == "content-length" || k == "host" { continue; }
        write!(s, "{k}: {}\r\n", v.as_str().unwrap()).unwrap();
    }
    write!(s, "\r\n").unwrap();
    s.write_all(&body).unwrap();
    let mut reader = BufReader::new(s);
    let mut status_line = String::new();
    reader.read_line(&mut status_line).unwrap();
    let status: u16 = status_line.split(' ').nth(1).unwrap().parse().unwrap();
    let mut headers = serde_json::Map::new();
    loop {
        let mut line = String::new();
        reader.read_line(&mut line).unwrap();
        let l = line.trim_end();
        if l.is_empty() { break; }
        let (k, v) = l.split_once(':').unwrap();
        headers.insert(k.to_ascii_lowercase(), json!(v.trim()));
    }
    let stream_id = call_id;
    engine.send(Inbound::Answer {
        call_id,
        result: Ok(json!({"status": status, "statusText": "OK", "headers": headers, "streamId": stream_id}).to_string()),
    });
    thread::spawn(move || {
        let mut buf = [0u8; 1024];
        loop {
            match reader.read(&mut buf) {
                Ok(0) => break,
                Ok(n) => { engine.send(Inbound::BodyChunk { stream_id, chunk: buf[..n].to_vec() }); }
                Err(e) => { engine.send(Inbound::BodyEnd { stream_id, error: Some(e.to_string()) }); return; }
            }
        }
        engine.send(Inbound::BodyEnd { stream_id, error: None });
    });
}

/// The host's session store: whole files by path, as `js/src/fs.js` expects.
type Files = Arc<Mutex<std::collections::BTreeMap<String, (String, u64)>>>;

fn now_ms() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as u64
}

fn fs_call(files: &Files, name: &str, p: &Value) -> Value {
    let mut f = files.lock().unwrap();
    let path = p["path"].as_str().unwrap_or_default().to_string();
    match name {
        "fs.read" => {
            let text = f.get(&path).map(|(t, _)| match p["maxLines"].as_u64() {
                Some(n) => t.split_inclusive('\n').take(n as usize).collect::<String>(),
                None => t.clone(),
            });
            json!({ "text": text })
        }
        "fs.write" => { f.insert(path, (p["text"].as_str().unwrap().to_string(), now_ms())); Value::Null }
        "fs.append" => {
            let e = f.entry(path).or_insert((String::new(), 0));
            e.0.push_str(p["text"].as_str().unwrap());
            e.1 = now_ms();
            Value::Null
        }
        "fs.rename" => {
            let v = f.remove(p["from"].as_str().unwrap()).unwrap();
            f.insert(p["to"].as_str().unwrap().to_string(), v);
            Value::Null
        }
        "fs.remove" => {
            let prefix = format!("{path}/");
            f.retain(|k, _| k != &path && !k.starts_with(&prefix));
            Value::Null
        }
        "fs.stat" => match f.get(&path) {
            Some((t, m)) => json!({ "size": t.len(), "mtimeMs": m }),
            None => Value::Null,
        },
        "fs.list" => {
            let dir = p["dir"].as_str().unwrap();
            let prefix = if dir == "/" { "/".to_string() } else { format!("{dir}/") };
            let files: Vec<Value> = f.iter().filter(|(k, _)| k.starts_with(&prefix))
                .map(|(k, (t, m))| json!({ "path": k, "size": t.len(), "mtimeMs": m })).collect();
            json!({ "files": files })
        }
        other => panic!("unknown fs call {other}"),
    }
}

struct Harness {
    engine: Arc<Engine>,
    files: Files,
    rx: Receiver<Outbound>,
    next_req: u64,
    events: Vec<(Instant, Value)>,
    approvals: Vec<Value>,
    tool_calls: Vec<Value>,
    deny: bool,
}

impl Harness {
    fn new() -> Self {
        Self::with_files(Files::default())
    }

    /// A fresh engine over an existing store, as after a relaunch.
    fn with_files(files: Files) -> Self {
        let (tx, rx) = mpsc::channel();
        let tx = Mutex::new(tx);
        let engine = Engine::spawn(Arc::new(move |o| { let _ = tx.lock().unwrap().send(o); })).unwrap();
        Self { engine: Arc::new(engine), files, rx, next_req: 1, events: vec![], approvals: vec![], tool_calls: vec![], deny: false }
    }

    /// An engine with the mock server registered as the custom provider `mock`.
    fn mocked(url: &str) -> Self {
        let mut h = Self::new();
        h.register(url);
        h
    }

    fn register(&mut self, url: &str) {
        self.ok("providers.setCustom", json!({"providers":[{
            "id":"mock","name":"Mock","api":"openai-completions","baseUrl":url,"models":[{"id":"mock"}]
        }]}));
    }

    fn ok(&mut self, method: &str, payload: Value) -> Value {
        let v = self.request(method, payload);
        assert_eq!(v["ok"], true, "{method}: {v}");
        v["value"].clone()
    }

    /// Roles of the messages on the current branch.
    fn roles(&mut self, session: &str) -> Vec<String> {
        let v = self.ok("session.entries", json!({"sessionId": session}));
        v["entries"].as_array().unwrap().iter()
            .map(|e| if e["type"] == "message" { e["message"]["role"].as_str().unwrap().to_string() } else { e["type"].as_str().unwrap().to_string() })
            .collect()
    }

    /// Sends a request and serves host calls until it resolves.
    fn request(&mut self, method: &str, payload: Value) -> Value {
        let req_id = self.next_req;
        self.next_req += 1;
        self.engine.send(Inbound::Request { req_id, method: method.into(), payload: payload.to_string() });
        let deadline = Instant::now() + Duration::from_secs(20);
        loop {
            let msg = self.rx.recv_timeout(deadline.saturating_duration_since(Instant::now()))
                .unwrap_or_else(|_| panic!("timed out waiting for {method}"));
            match msg {
                Outbound::Result { req_id: id, payload } if id == req_id => {
                    let v: Value = serde_json::from_str(&payload).unwrap();
                    return v;
                }
                Outbound::HostCall { call_id, name, payload, body } => match name.as_str() {
                    "fetch" => {
                        let engine = self.engine.clone();
                        thread::spawn(move || do_fetch(engine, call_id, &payload, body));
                    }
                    "tool" => {
                        let p: Value = serde_json::from_str(&payload).unwrap();
                        self.tool_calls.push(p);
                        self.engine.send(Inbound::Answer { call_id, result: Ok(json!({"content":[{"type":"text","text":"12:00 UTC"}]}).to_string()) });
                    }
                    "approve" => {
                        let p: Value = serde_json::from_str(&payload).unwrap();
                        self.approvals.push(p);
                        let engine = self.engine.clone();
                        let deny = self.deny;
                        // Answered late, as a user would.
                        thread::spawn(move || {
                            thread::sleep(Duration::from_millis(100));
                            engine.send(Inbound::Answer { call_id, result: Ok(json!({"block": deny, "reason": "no"}).to_string()) });
                        });
                    }
                    "auth.read" => {
                        self.engine.send(Inbound::Answer { call_id, result: Ok(json!({"type":"api_key","key":"test"}).to_string()) });
                    }
                    "auth.list" => {
                        self.engine.send(Inbound::Answer { call_id, result: Ok(json!([{"providerId":"mock","type":"api_key"}]).to_string()) });
                    }
                    n if n.starts_with("fs.") => {
                        let p: Value = serde_json::from_str(&payload).unwrap();
                        let v = fs_call(&self.files, n, &p);
                        self.engine.send(Inbound::Answer { call_id, result: Ok(v.to_string()) });
                    }
                    other => panic!("unexpected host call {other}"),
                },
                Outbound::Event { payload } => self.events.push((Instant::now(), serde_json::from_str(&payload).unwrap())),
                Outbound::Fatal { message } => panic!("fatal: {message}"),
                Outbound::Log { level, message } if level == "error" => eprintln!("[js error] {message}"),
                _ => {}
            }
        }
    }
}

/// The mock server's model, as a reference: `Harness::mocked` registers the
/// custom provider it belongs to.
fn model(_base_url: &str) -> Value {
    json!({"provider":"mock","id":"mock"})
}

fn tool_def() -> Value {
    json!({"name":"get_time","description":"Get the time","parameters":{"type":"object","properties":{"tz":{"type":"string"}}}})
}

#[test]
fn runtime_info() {
    let mut h = Harness::new();
    let v = h.request("runtime.info", json!({}));
    assert_eq!(v["ok"], true, "{v}");
    assert_eq!(v["value"]["piAgentCore"], "0.87.1");
}

#[test]
fn unknown_method_is_an_error_not_a_crash() {
    let mut h = Harness::new();
    let v = h.request("nope", json!({}));
    assert_eq!(v["ok"], false);
    assert!(v["error"].as_str().unwrap().contains("Unknown method"));
}

fn open(h: &mut Harness, id: &str, model: Value, extra: Value) -> Value {
    let mut p = json!({"sessionId": id, "model": model});
    for (k, v) in extra.as_object().unwrap() { p[k] = v.clone(); }
    h.ok("session.open", p)
}

#[test]
fn prompt_streams_calls_tools_and_waits_for_approval() {
    let (url, seen) = mock_server(Duration::from_millis(120));
    let mut h = Harness::mocked(&url);
    open(&mut h, "s1", model(&url), json!({"systemPrompt":"test","tools":[tool_def()],"approval":true}));

    let v = h.ok("session.prompt", json!({"sessionId":"s1","text":"What time is it?"}));
    assert_eq!(v["result"]["status"], "completed", "{v}");
    assert_eq!(h.roles("s1"), ["user", "assistant", "toolResult", "assistant"]);
    let entries = h.ok("session.entries", json!({"sessionId":"s1"}));
    let last = entries["entries"].as_array().unwrap().last().unwrap()["message"].clone();
    assert_eq!(last["content"][0]["text"], "It is 12:00.");

    // The approval was asked for, and the tool ran only after it.
    assert_eq!(h.approvals.len(), 1);
    assert_eq!(h.approvals[0]["name"], "get_time");
    assert_eq!(h.tool_calls.len(), 1);
    assert_eq!(h.tool_calls[0]["args"]["tz"], "UTC");

    // Streamed: the deltas arrived spread out, not in one burst at the end.
    let deltas: Vec<Instant> = h.events.iter()
        .filter(|(_, e)| e["event"]["type"] == "message_update" && e["event"]["event"]["type"] == "text_delta")
        .map(|(t, _)| *t).collect();
    assert_eq!(deltas.len(), 4);
    assert!(deltas[3] - deltas[0] >= Duration::from_millis(300), "deltas not streamed: {:?}", deltas[3] - deltas[0]);

    let reqs = seen.lock().unwrap();
    assert_eq!(reqs.len(), 2);
    assert!(reqs[1]["messages"].as_array().unwrap().iter().any(|m| m["role"] == "tool"));
}

#[test]
fn a_session_survives_a_relaunch() {
    let (url, _) = mock_server(Duration::from_millis(1));
    let files = {
        let mut h = Harness::mocked(&url);
        open(&mut h, "keep", model(&url), json!({}));
        h.ok("session.prompt", json!({"sessionId":"keep","text":"hi"}));
        h.ok("session.close", json!({"sessionId":"keep"}));
        h.files.clone()
    };
    // A new engine over the same store: the conversation is still there.
    let mut h = Harness::with_files(files);
    h.register(&url);
    let list = h.ok("sessions.list", json!({}));
    assert_eq!(list[0]["id"], "keep");
    let v = open(&mut h, "keep", model(&url), json!({}));
    assert_eq!(v["entries"].as_array().unwrap().len(), 2, "{v}");
    h.ok("session.prompt", json!({"sessionId":"keep","text":"again"}));
    assert_eq!(h.roles("keep"), ["user", "assistant", "user", "assistant"]);
    h.ok("session.close", json!({"sessionId":"keep"}));
    h.ok("sessions.delete", json!({"sessionId":"keep"}));
    assert_eq!(h.ok("sessions.list", json!({})).as_array().unwrap().len(), 0);
}

#[test]
fn navigating_back_branches_instead_of_overwriting() {
    let (url, _) = mock_server(Duration::from_millis(1));
    let mut h = Harness::mocked(&url);
    open(&mut h, "b", model(&url), json!({}));
    h.ok("session.prompt", json!({"sessionId":"b","text":"first"}));
    let entries = h.ok("session.entries", json!({"sessionId":"b"}));
    let first_user = entries["entries"][0]["id"].as_str().unwrap().to_string();
    // Edit the first message: go back to before it and ask something else.
    h.ok("session.navigate", json!({"sessionId":"b","targetId":null}));
    h.ok("session.prompt", json!({"sessionId":"b","text":"edited"}));
    let branch = h.ok("session.entries", json!({"sessionId":"b"}));
    assert_eq!(branch["entries"][0]["message"]["content"][0]["text"], "edited");
    // The original is still in the tree.
    let tree = h.ok("session.tree", json!({"sessionId":"b"}));
    assert!(tree["entries"].as_array().unwrap().iter().any(|e| e["id"] == first_user.as_str()));
    assert_eq!(tree["entries"].as_array().unwrap().iter().filter(|e| e["type"] == "message").count(), 4);
}

#[test]
fn denied_tool_does_not_run() {
    let (url, _) = mock_server(Duration::from_millis(10));
    let mut h = Harness::mocked(&url);
    h.deny = true;
    open(&mut h, "s", model(&url), json!({"tools":[tool_def()],"approval":true}));
    h.ok("session.prompt", json!({"sessionId":"s","text":"time?"}));
    assert_eq!(h.approvals.len(), 1);
    assert!(h.tool_calls.is_empty());
}

#[test]
fn abort_stops_a_running_prompt() {
    let (url, _) = mock_server(Duration::from_millis(400));
    let mut h = Harness::mocked(&url);
    open(&mut h, "s", model(&url), json!({}));
    let engine = h.engine.clone();
    thread::spawn(move || {
        thread::sleep(Duration::from_millis(500));
        engine.send(Inbound::Request { req_id: 999, method: "session.abort".into(), payload: json!({"sessionId":"s"}).to_string() });
    });
    let started = Instant::now();
    let v = h.ok("session.prompt", json!({"sessionId":"s","text":"hi"}));
    assert_eq!(v["result"]["status"], "aborted", "{v}");
    assert!(started.elapsed() < Duration::from_millis(1500));
}

#[test]
fn compaction_summarises_for_the_model_and_keeps_the_originals() {
    let (url, seen) = mock_server(Duration::from_millis(1));
    let mut h = Harness::mocked(&url);
    open(&mut h, "c", model(&url), json!({"compaction":{"keepRecentTokens":1}}));
    let long = "word ".repeat(200);
    for i in 0..3 {
        h.ok("session.prompt", json!({"sessionId":"c","text":format!("turn{i} {long}")}));
    }
    let before = h.roles("c");

    let v = h.ok("session.compact", json!({"sessionId":"c"}));
    assert_eq!(v["compaction"]["status"], "completed", "{v}");
    let compaction = v["entries"].as_array().unwrap().iter().find(|e| e["type"] == "compaction").unwrap().clone();
    assert!(compaction["summary"].as_str().unwrap().starts_with("SUMMARY"), "{compaction}");

    // The branch still holds every message — a UI shows the whole conversation —
    // with the compaction marked where it happened.
    let after = h.roles("c");
    assert_eq!(after.len(), before.len() + 1, "{after:?}");

    // The model, though, now gets the summary instead of the old turns.
    h.ok("session.prompt", json!({"sessionId":"c","text":"next"}));
    let last = seen.lock().unwrap().last().unwrap().to_string();
    assert!(last.contains("SUMMARY"), "{last}");
    assert!(!last.contains("turn0"), "{last}");
}

#[test]
fn one_shot_completion() {
    let (url, _) = mock_server(Duration::from_millis(1));
    let mut h = Harness::mocked(&url);
    let v = h.request("complete", json!({"model":model(&url),"messages":[{"role":"user","content":"hi","timestamp":1}],"streamId":7}));
    assert_eq!(v["ok"], true, "{v}");
    assert_eq!(v["value"]["content"][0]["text"], "It is 12:00.");
    let n = h.events.iter().filter(|(_, e)| e["type"] == "complete.event" && e["streamId"] == 7).count();
    assert!(n >= 4);
    let _ = HashMap::<u8, u8>::new();
}

#[test]
fn the_catalog_is_pi_ais_and_custom_providers_join_it() {
    let (url, _) = mock_server(Duration::from_millis(1));
    let mut h = Harness::mocked(&url);
    let providers = h.ok("providers.list", json!({}));
    let ids: Vec<&str> = providers.as_array().unwrap().iter().map(|p| p["id"].as_str().unwrap()).collect();
    assert!(ids.contains(&"openai") && ids.contains(&"anthropic") && ids.contains(&"openrouter"), "{ids:?}");
    // What cannot authenticate outside Node is left out.
    assert!(!ids.contains(&"amazon-bedrock"));
    let mock = providers.as_array().unwrap().iter().find(|p| p["id"] == "mock").unwrap();
    assert_eq!(mock["custom"], true);
    assert_eq!(mock["models"][0]["id"], "mock");
    let openai = providers.as_array().unwrap().iter().find(|p| p["id"] == "openai").unwrap();
    assert!(openai["models"].as_array().unwrap().iter().all(|m| m["contextWindow"].as_u64().unwrap() > 0));
}
