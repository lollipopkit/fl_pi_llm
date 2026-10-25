//! The Rust host end to end: a session over a mock OpenAI-compatible server,
//! HTTP by `ReqwestFetch`, a tool and an approval answered in Rust, the
//! session kept under a directory and reopened by a fresh runtime.

#![cfg(feature = "reqwest")]

use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use fl_pi_llm::host::{
    Approval, Approver, BoxFuture, Cancel, Config, Credentials, OpenSession, ReqwestFetch, Runtime, Tool,
    ToolCall, ToolDef, ToolResult,
};
use serde_json::{json, Value};

mod common;

struct Key;

impl Credentials for Key {
    fn read(&self, _: &str) -> BoxFuture<'_, Result<Option<Value>, String>> {
        Box::pin(async { Ok(Some(json!({ "type": "api_key", "key": "test" }))) })
    }
    fn list(&self) -> BoxFuture<'_, Result<Vec<String>, String>> {
        Box::pin(async { Ok(vec!["mock".into()]) })
    }
    fn write(&self, _: &str, _: Value) -> BoxFuture<'_, Result<(), String>> {
        Box::pin(async { Ok(()) })
    }
    fn delete(&self, _: &str) -> BoxFuture<'_, Result<(), String>> {
        Box::pin(async { Ok(()) })
    }
}

#[derive(Default)]
struct Clock {
    calls: Mutex<Vec<ToolCall>>,
}

impl Tool for Clock {
    fn def(&self) -> ToolDef {
        ToolDef {
            name: "get_time".into(),
            description: "Get the time".into(),
            parameters: json!({ "type": "object", "properties": { "tz": { "type": "string" } } }),
            label: None,
            sequential: false,
        }
    }

    fn execute(&self, call: ToolCall, _: Cancel) -> BoxFuture<'_, Result<ToolResult, String>> {
        self.calls.lock().unwrap().push(call);
        Box::pin(async { Ok(ToolResult::text("12:00 UTC").with_details(json!({ "shown": true }))) })
    }
}

struct Asked(AtomicUsize, bool);

impl Approver for Asked {
    fn approve(&self, _: ToolCall) -> BoxFuture<'_, Approval> {
        self.0.fetch_add(1, Ordering::SeqCst);
        let deny = self.1;
        Box::pin(async move {
            // Answered late, as a person would.
            tokio::time::sleep(Duration::from_millis(50)).await;
            if deny { Approval::Deny(Some("no".into())) } else { Approval::Allow }
        })
    }
}

fn runtime(dir: &std::path::Path) -> Runtime {
    let client = reqwest::Client::builder().redirect(reqwest::redirect::Policy::none()).build().unwrap();
    Runtime::start(Config {
        dir: dir.to_path_buf(),
        key: Some(fl_pi_llm::db::Key::new(&[4; 32]).unwrap()),
        credentials: Arc::new(Key),
        fetch: Arc::new(ReqwestFetch::new(client)),
        logger: None,
    })
    .unwrap()
}

async fn register(rt: &Runtime, url: &str) {
    rt.set_custom_providers(json!([{ "id": "mock", "name": "Mock", "api": "openai-completions", "baseUrl": url, "models": [{ "id": "mock" }] }]))
        .await
        .unwrap();
}

fn roles(entries: &[Value]) -> Vec<String> {
    entries
        .iter()
        .map(|e| if e["type"] == "message" { e["message"]["role"].as_str().unwrap().to_string() } else { e["type"].as_str().unwrap().to_string() })
        .collect()
}

fn temp(name: &str) -> std::path::PathBuf {
    let d = std::env::temp_dir().join(format!("fl_pi_llm-host-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&d);
    d
}

#[tokio::test(flavor = "multi_thread")]
async fn a_session_runs_its_tools_in_rust_and_survives_a_restart() {
    let (url, seen) = common::mock_server(Duration::ZERO);
    let dir = temp("restart");
    let clock = Arc::new(Clock::default());
    let asked = Arc::new(Asked(AtomicUsize::new(0), false));
    {
        let rt = runtime(&dir);
        register(&rt, &url).await;
        let (session, mut events) = rt
            .open_session(OpenSession {
                id: "s1".into(),
                model: json!({ "provider": "mock", "id": "mock" }),
                system_prompt: "Be brief.".into(),
                tools: vec![clock.clone()],
                approver: Some(asked.clone()),
                thinking_level: None,
                compaction: None,
            })
            .await
            .unwrap();
        let result = session.prompt("What time is it?", None).await.unwrap();
        assert_ne!(result["status"], "error", "{result}");
        assert_eq!(asked.0.load(Ordering::SeqCst), 1);
        let calls = clock.calls.lock().unwrap().clone();
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].args, json!({ "tz": "UTC" }));
        assert_eq!(calls[0].session_id, "s1");

        let entries = session.entries().await.unwrap();
        assert_eq!(roles(&entries), ["user", "assistant", "toolResult", "assistant"]);
        assert_eq!(entries[2]["message"]["details"], json!({ "shown": true }));
        let text = entries[3]["message"]["content"][0]["text"].as_str().unwrap();
        assert_eq!(text, "It is 12:00.");

        let mut types = Vec::new();
        while let Ok(e) = events.try_recv() {
            types.push(e["type"].as_str().unwrap_or_default().to_string());
        }
        assert!(types.contains(&"tool_start".to_string()) && types.contains(&"tool_end".to_string()), "{types:?}");
        // The mock answers at once: each answer streams as one update.
        assert!(types.iter().filter(|t| *t == "message_update").count() >= 1, "{types:?}");

        // The model was told the system prompt.
        assert_eq!(seen.lock().unwrap()[0]["messages"][0]["content"], "Be brief.");
        session.close().await.unwrap();
    }
    // A fresh runtime over the same directory: what a restarted agent sees.
    let rt = runtime(&dir);
    register(&rt, &url).await;
    let listed = rt.sessions().await.unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0]["id"], "s1");
    let (session, _events) = rt
        .open_session(OpenSession {
            id: "s1".into(),
            model: json!({ "provider": "mock", "id": "mock" }),
            system_prompt: String::new(),
            tools: vec![],
            approver: None,
            thinking_level: None,
            compaction: None,
        })
        .await
        .unwrap();
    assert!(!session.interrupted());
    assert_eq!(session.entries().await.unwrap().len(), 4);
    assert!(rt.open_session(OpenSession {
        id: "s1".into(),
        model: json!({ "provider": "mock", "id": "mock" }),
        system_prompt: String::new(),
        tools: vec![],
        approver: None,
        thinking_level: None,
        compaction: None,
    })
    .await
    .is_err(), "a session opens once");
    session.close().await.unwrap();
    rt.delete_session("s1").await.unwrap();
    assert!(rt.sessions().await.unwrap().is_empty());
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test(flavor = "multi_thread")]
async fn a_denied_call_never_runs() {
    let (url, _) = common::mock_server(Duration::ZERO);
    let dir = temp("deny");
    let rt = runtime(&dir);
    register(&rt, &url).await;
    let clock = Arc::new(Clock::default());
    let (session, _events) = rt
        .open_session(OpenSession {
            id: "s".into(),
            model: json!({ "provider": "mock", "id": "mock" }),
            system_prompt: String::new(),
            tools: vec![clock.clone()],
            approver: Some(Arc::new(Asked(AtomicUsize::new(0), true))),
            thinking_level: None,
            compaction: None,
        })
        .await
        .unwrap();
    session.prompt("What time is it?", None).await.unwrap();
    assert!(clock.calls.lock().unwrap().is_empty());
    let entries = session.entries().await.unwrap();
    let result = entries.iter().find(|e| e["message"]["role"] == "toolResult").unwrap();
    assert_eq!(result["message"]["isError"], true);
    session.close().await.unwrap();
    let _ = std::fs::remove_dir_all(dir);
}

#[tokio::test(flavor = "multi_thread")]
async fn plain_http_off_this_machine_is_refused() {
    use fl_pi_llm::host::{Fetch, FetchRequest};
    let fetch = ReqwestFetch::new(reqwest::Client::new());
    let req = |url: &str| FetchRequest { url: url.into(), method: "POST".into(), headers: vec![], body: None };
    let refused = fetch.fetch(req("http://192.0.2.1:9/v1/chat/completions")).await.err().unwrap();
    assert!(refused.contains("fetch refused"), "{refused}");
    fetch.set_insecure_origins(vec!["http://192.0.2.1:9".into()]);
    // Allowed now: it fails connecting, not on the policy.
    let failed = tokio::time::timeout(Duration::from_secs(1), fetch.fetch(req("http://192.0.2.1:9/v1"))).await;
    assert!(failed.is_err() || !failed.unwrap().err().unwrap().contains("fetch refused"));
}
