//! What the tests share: a mock OpenAI-compatible server.
#![allow(dead_code)]

use std::io::{BufRead, BufReader, Read, Write};
use std::net::TcpListener;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::Duration;

use serde_json::{json, Value};

/// An OpenAI chat-completions server that streams. The first request gets a
/// tool call; any request carrying a tool result gets text, one word per chunk.
pub fn mock_server(delay: Duration) -> (String, Arc<Mutex<Vec<Value>>>) {
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

