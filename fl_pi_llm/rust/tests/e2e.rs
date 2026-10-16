//! The whole path, minus Dart: the bundle on QuickJS, host calls answered by a
//! test host that does real HTTP against a mock OpenAI-compatible server.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpStream;
use std::sync::mpsc::{self, Receiver};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

use fl_pi_llm::engine::{Engine, Inbound, Outbound};

mod common;
use common::mock_server;
use serde_json::{json, Value};

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

/// Sessions from before pi-durable, as the host keeps them: appended chunks
/// by path. TODO: remove with `js/src/legacy.js`.
type Legacy = Arc<Mutex<std::collections::BTreeMap<String, Vec<String>>>>;

fn now_ms() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as u64
}

fn legacy_call(legacy: &Legacy, name: &str, p: &Value) -> Value {
    let mut l = legacy.lock().unwrap();
    let path = p["path"].as_str().unwrap_or_default();
    match name {
        "legacy.list" => {
            let files: Vec<Value> = l.iter()
                .map(|(k, c)| json!({ "path": k, "size": c.iter().map(String::len).sum::<usize>(), "mtimeMs": now_ms() })).collect();
            json!({ "files": files })
        }
        "legacy.read" => {
            let after = p["after"].as_i64().unwrap();
            let max = p["maxChars"].as_u64().unwrap() as usize;
            let mut out = vec![];
            let mut n = 0;
            for (seq, text) in l.get(path).into_iter().flatten().enumerate().skip((after + 1) as usize) {
                if !out.is_empty() && n + text.len() > max { break; }
                n += text.len();
                out.push(json!([seq, text]));
            }
            json!({ "chunks": out })
        }
        "legacy.remove" => { l.remove(path); Value::Null }
        other => panic!("unknown legacy call {other}"),
    }
}

/// A directory of its own for each engine's chats.
fn temp_dir() -> std::path::PathBuf {
    static NEXT: std::sync::atomic::AtomicU32 = std::sync::atomic::AtomicU32::new(0);
    let n = NEXT.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
    let d = std::env::temp_dir().join(format!("fl_pi_llm_e2e_{}_{n}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

struct Harness {
    engine: Arc<Engine>,
    dir: std::path::PathBuf,
    legacy: Legacy,
    rx: Receiver<Outbound>,
    next_req: u64,
    events: Vec<(Instant, Value)>,
    approvals: Vec<Value>,
    tool_calls: Vec<Value>,
    deny: bool,
}

impl Harness {
    fn new() -> Self {
        Self::with_store(temp_dir(), Legacy::default())
    }

    /// A fresh engine over an existing store, as after a relaunch.
    fn with_store(dir: std::path::PathBuf, legacy: Legacy) -> Self {
        let (tx, rx) = mpsc::channel();
        let tx = Mutex::new(tx);
        let engine = Engine::spawn(Arc::new(move |o| { let _ = tx.lock().unwrap().send(o); }), Some(dir.clone())).unwrap();
        Self { engine: Arc::new(engine), dir, legacy, rx, next_req: 1, events: vec![], approvals: vec![], tool_calls: vec![], deny: false }
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
                    n if n.starts_with("legacy.") => {
                        let p: Value = serde_json::from_str(&payload).unwrap();
                        let v = legacy_call(&self.legacy, n, &p);
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
    assert_eq!(v["value"]["piDurable"], "1.1.0");
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
    // pi-durable commits a partial answer at most every 100 ms, so deltas
    // that came closer together arrive as one.
    let deltas: Vec<Instant> = h.events.iter()
        .filter(|(_, e)| e["event"]["type"] == "message_update" && e["event"]["event"]["type"] == "text_delta")
        .map(|(t, _)| *t).collect();
    assert!(deltas.len() >= 3, "{}", deltas.len());
    let spread = *deltas.last().unwrap() - deltas[0];
    assert!(spread >= Duration::from_millis(200), "deltas not streamed: {spread:?}");

    let reqs = seen.lock().unwrap();
    assert_eq!(reqs.len(), 2);
    assert!(reqs[1]["messages"].as_array().unwrap().iter().any(|m| m["role"] == "tool"));
}

#[test]
fn a_session_survives_a_relaunch() {
    let (url, _) = mock_server(Duration::from_millis(1));
    let dir = {
        let mut h = Harness::mocked(&url);
        open(&mut h, "keep", model(&url), json!({}));
        h.ok("session.prompt", json!({"sessionId":"keep","text":"hi"}));
        h.ok("session.close", json!({"sessionId":"keep"}));
        h.dir.clone()
    };
    // A new engine over the same store: the conversation is still there.
    let mut h = Harness::with_store(dir, Legacy::default());
    h.register(&url);
    let list = h.ok("sessions.list", json!({}));
    assert_eq!(list[0]["id"], "keep");
    open(&mut h, "keep", model(&url), json!({}));
    assert_eq!(h.roles("keep"), ["user", "assistant"]);
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

/// A chat is read a page at a time, newest first, each page starting at a
/// user message; the versions of a message come with it.
#[test]
fn the_branch_is_read_in_pages_with_its_versions() {
    let (url, _) = mock_server(Duration::from_millis(1));
    let mut h = Harness::mocked(&url);
    open(&mut h, "p", model(&url), json!({}));
    for i in 0..4 {
        h.ok("session.prompt", json!({"sessionId":"p","text":format!("q{i}")}));
    }
    // Ask "q3" again: a second version of it.
    let all = h.ok("session.entries", json!({"sessionId":"p"}))["entries"].as_array().unwrap().clone();
    assert_eq!(all.len(), 8);
    let q3 = all[6].clone();
    h.ok("session.navigate", json!({"sessionId":"p","targetId":q3["parentId"]}));
    h.ok("session.prompt", json!({"sessionId":"p","text":"q3 again"}));

    let page = h.ok("session.page", json!({"sessionId":"p","limit":2}));
    let entries = page["entries"].as_array().unwrap();
    assert_eq!(page["more"], true);
    assert_eq!(entries.len(), 2, "{page}");
    assert_eq!(entries[0]["message"]["content"][0]["text"], "q3 again");
    let versions: Vec<_> = entries[0]["versions"].as_array().unwrap().iter().map(|v| v["message"]["content"][0]["text"].clone()).collect();
    assert_eq!(versions, [json!("q3"), json!("q3 again")]);

    // Three asked for; four given, back to the user message the reply answers.
    let earlier = h.ok("session.page", json!({"sessionId":"p","limit":3,"before":entries[0]["id"]}));
    let earlier = earlier["entries"].as_array().unwrap().clone();
    assert_eq!(earlier.len(), 4);
    assert_eq!(earlier[0]["message"]["content"][0]["text"], "q1");
    assert_eq!(earlier[3]["id"], entries[0]["parentId"], "the pages join");
    assert!(earlier[0]["versions"].is_null(), "one version is no versions");

    // Back to the first version, and its reply with it.
    h.ok("session.switchTo", json!({"sessionId":"p","entryId":q3["id"]}));
    let branch = h.ok("session.entries", json!({"sessionId":"p"}))["entries"].as_array().unwrap().clone();
    assert_eq!(branch.len(), 8);
    assert_eq!(branch[6]["id"], q3["id"]);
    assert_eq!(branch[7]["message"]["role"], "assistant");
    // The other version is still one entry away.
    let found = h.ok("session.entry", json!({"sessionId":"p","entryId":entries[0]["id"]}));
    assert_eq!(found["entry"]["message"]["content"][0]["text"], "q3 again");
}

/// flutter_server_box#1718: a session from before pi-durable larger than
/// the engine's whole heap moves over, opens, and reads a page at a time.
/// Compacted every 50 turns, as a long chat is. Heavy: some 600 MB.
#[test]
#[ignore = "heavy: cargo test --release --test e2e -- --ignored a_session_larger"]
fn a_session_larger_than_the_heap_still_opens() {
    let (url, _) = mock_server(Duration::from_millis(1));
    let big = "x".repeat(1 << 20);
    let mut chunks = vec![];
    let mut parent = Value::Null;
    for i in 0..600u32 {
        let id = format!("e{i}");
        let entry = if i % 50 == 49 {
            json!({"kind":"entry","id":id,"parentId":parent,"type":"compaction","summary":format!("summary {i}"),"seq":i,"timestamp":i})
        } else {
            json!({"kind":"entry","id":id,"parentId":parent,"type":"message","seq":i,"timestamp":i,
                "message":{"role":"user","content":[{"type":"text","text":format!("{i} {big}")}],"timestamp":i}})
        };
        chunks.push(format!("{entry}\n"));
        parent = json!(id);
    }
    chunks.push(format!("{}\n", json!({"kind":"value","op":"set","seq":600,"namespace":"pi.branch.tip","key":"main","value":parent})));
    let (legacy, old) = legacy_store(chunks);

    let dir = temp_dir();
    let mut h = Harness::with_store(dir.clone(), legacy.clone());
    h.register(&url);
    open(&mut h, "chat-1", model(&url), json!({}));
    assert!(!legacy.lock().unwrap().contains_key(&old));
    let size: u64 = std::fs::read_dir(dir.join("chats")).unwrap().map(|e| e.unwrap().metadata().unwrap().len()).sum();
    assert!(size > 550 << 20, "{size}");

    let page = h.ok("session.page", json!({"sessionId":"chat-1","limit":3}));
    assert_eq!(page["more"], true);
    let entries = page["entries"].as_array().unwrap();
    assert_eq!(entries.last().unwrap()["summary"], "summary 599");
    let earlier = h.ok("session.page", json!({"sessionId":"chat-1","limit":3,"before":entries[0]["id"]}));
    assert!(!earlier["entries"].as_array().unwrap().is_empty());
    h.ok("session.switchTo", json!({"sessionId":"chat-1","entryId":entries[0]["id"]}));
    h.ok("session.close", json!({"sessionId":"chat-1"}));

    // And again after a relaunch, from its own file.
    let mut h = Harness::with_store(dir.clone(), Legacy::default());
    h.register(&url);
    open(&mut h, "chat-1", model(&url), json!({}));
    let page = h.ok("session.page", json!({"sessionId":"chat-1","limit":3}));
    assert_eq!(page["entries"].as_array().unwrap().last().unwrap()["summary"], "summary 599");
    let _ = std::fs::remove_dir_all(&dir);
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
    let branch = h.ok("session.entries", json!({"sessionId":"c"}));
    let compaction = branch["entries"].as_array().unwrap().iter().find(|e| e["type"] == "compaction").unwrap().clone();
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

/// A session pi-agent-core 0.87.1 wrote: "q1" with a tool call, "q2", then
/// "q2" edited into "q2 edited", a custom entry, a compaction, and a name.
/// TODO: remove with `js/src/legacy.js`.
const LEGACY: &str = include_str!("fixtures/legacy-0.87.1.jsonl");

/// [LEGACY] as the host keeps it: [chunks] of it, each one append.
fn legacy_store(chunks: Vec<String>) -> (Legacy, String) {
    let old = "/sessions/----/2026-10-12T13-14-14-726Z_chat-1.jsonl".to_string();
    let legacy = Legacy::default();
    legacy.lock().unwrap().insert(old.clone(), chunks);
    (legacy, old)
}

#[test]
fn a_legacy_session_moves_over_with_its_versions() {
    let (url, _) = mock_server(Duration::from_millis(1));
    let (legacy, old) = legacy_store(LEGACY.split_inclusive('\n').map(String::from).collect());
    let mut h = Harness::with_store(temp_dir(), legacy.clone());
    h.register(&url);

    let listed = h.ok("sessions.list", json!({}));
    assert_eq!(listed[0]["id"], "chat-1", "listed before it is moved");

    let v = open(&mut h, "chat-1", model(&url), json!({}));
    assert_eq!(v["name"], "Named");
    // The branch it stood on: the edited one, where the compaction was made.
    assert_eq!(
        h.roles("chat-1"),
        ["user", "assistant", "toolResult", "assistant", "user", "assistant", "custom", "compaction"],
    );
    let branch = h.ok("session.entries", json!({"sessionId":"chat-1"}));
    let texts: Vec<String> = branch["entries"].as_array().unwrap().iter()
        .filter(|e| e["message"]["role"] == "user")
        .map(|e| e["message"]["content"][0]["text"].as_str().unwrap().to_string()).collect();
    assert_eq!(texts, ["q1", "q2 edited"]);
    let compaction = branch["entries"].as_array().unwrap().last().unwrap().clone();
    assert_eq!(compaction["summary"], "summary of earlier", "{compaction}");
    // The version the edit replaced is still there.
    let tree = h.ok("session.tree", json!({"sessionId":"chat-1"}));
    assert!(tree["entries"].as_array().unwrap().iter().any(|e| e["message"]["content"][0]["text"] == "q2"));
    // Every entry still hangs off the one before it.
    let ids: std::collections::HashSet<_> = tree["entries"].as_array().unwrap().iter().map(|e| e["id"].clone()).collect();
    assert!(tree["entries"].as_array().unwrap().iter().all(|e| e["parentId"].is_null() || ids.contains(&e["parentId"])));

    // The old file is gone; the chat goes on where it was.
    assert!(!legacy.lock().unwrap().contains_key(&old));
    h.ok("session.prompt", json!({"sessionId":"chat-1","text":"after"}));
    assert_eq!(h.roles("chat-1").len(), 10);
    h.ok("session.close", json!({"sessionId":"chat-1"}));
    let listed = h.ok("sessions.list", json!({}));
    assert_eq!(listed.as_array().unwrap().len(), 1);
}

/// Chunks need not end where lines do: a file rewritten whole is one chunk,
/// and a torn append leaves a line across two.
#[test]
fn a_legacy_session_moves_over_whatever_its_chunks() {
    let (url, _) = mock_server(Duration::from_millis(1));
    let whole = vec![LEGACY.to_string()];
    let bytes: Vec<char> = LEGACY.chars().collect();
    let torn: Vec<String> = bytes.chunks(97).map(|c| c.iter().collect()).collect();
    for chunks in [whole, torn] {
        let (legacy, old) = legacy_store(chunks);
        let mut h = Harness::with_store(temp_dir(), legacy.clone());
        h.register(&url);
        h.ok("sessions.migrate", json!({}));
        assert!(!legacy.lock().unwrap().contains_key(&old));
        let v = open(&mut h, "chat-1", model(&url), json!({}));
        assert_eq!(v["name"], "Named");
        assert_eq!(
            h.roles("chat-1"),
            ["user", "assistant", "toolResult", "assistant", "user", "assistant", "custom", "compaction"],
        );
    }
}

/// A move cut short leaves the old session; the next open starts it over.
#[test]
fn a_legacy_move_cut_short_starts_over() {
    let (url, _) = mock_server(Duration::from_millis(1));
    let (legacy, old) = legacy_store(LEGACY.split_inclusive('\n').map(String::from).collect());
    let dir = temp_dir();
    // What a move killed halfway leaves: the chat's file, and the old session.
    {
        let mut h = Harness::with_store(dir.clone(), Legacy::default());
        h.register(&url);
        open(&mut h, "chat-1", model(&url), json!({}));
        h.ok("session.prompt", json!({"sessionId":"chat-1","text":"half"}));
        h.ok("session.close", json!({"sessionId":"chat-1"}));
    }
    let mut h = Harness::with_store(dir, legacy.clone());
    h.register(&url);
    open(&mut h, "chat-1", model(&url), json!({}));
    assert!(!legacy.lock().unwrap().contains_key(&old));
    assert_eq!(h.roles("chat-1").len(), 8, "{:?}", h.roles("chat-1"));
}

/// What `pi` reads: the session as a v3 file, every version kept, the one the
/// chat stands on last.
#[test]
fn a_session_exports_as_a_pi_session_file() {
    let (url, _) = mock_server(Duration::from_millis(1));
    let mut h = Harness::mocked(&url);
    open(&mut h, "x", model(&url), json!({}));
    h.ok("session.prompt", json!({"sessionId":"x","text":"first"}));
    h.ok("session.navigate", json!({"sessionId":"x","targetId":null}));
    h.ok("session.prompt", json!({"sessionId":"x","text":"second"}));
    h.ok("session.setName", json!({"sessionId":"x","name":"Named"}));
    let text = h.ok("session.exportPi", json!({"sessionId":"x","cwd":"/home/u"}))["text"].as_str().unwrap().to_string();
    let lines: Vec<Value> = text.lines().map(|l| serde_json::from_str(l).unwrap()).collect();
    assert_eq!(lines[0]["type"], "session");
    assert_eq!(lines[0]["version"], 3);
    assert_eq!(lines[0]["cwd"], "/home/u");
    let messages: Vec<&Value> = lines.iter().filter(|l| l["type"] == "message").collect();
    assert_eq!(messages.len(), 4, "{text}");
    assert!(lines.iter().any(|l| l["type"] == "session_info" && l["name"] == "Named"));
    // pi continues from the last line: the answer to "second".
    let last = lines.last().unwrap();
    assert_eq!(last["message"]["role"], "assistant", "{text}");
    let parent = lines.iter().find(|l| l["id"] == last["parentId"]).unwrap();
    assert_eq!(parent["message"]["content"][0]["text"], "second");
    for l in &lines[1..] {
        assert!(l["parentId"].is_null() || lines.iter().any(|o| o["id"] == l["parentId"]), "{l}");
    }
}
