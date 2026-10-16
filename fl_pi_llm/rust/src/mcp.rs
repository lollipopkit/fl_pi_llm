//! What an MCP server's tools become for the model, the one implementation
//! for the apps (`api::mcp`, over the bridge; their client is mcp_dart, which
//! signs in through a browser) and a Rust host (`host::mcp`, its own client):
//! a tool's name (`<server id>__<tool>`, the id made from the server's
//! address), what it says and is labelled, the servers' instructions for the
//! system prompt, and a call's answer as pi content.

use serde_json::{Value, json};

/// Providers take tool names of at most this many characters.
const MAX_NAME: usize = 64;
/// What the system prompt carries of a server's instructions.
pub const MAX_INSTRUCTIONS: usize = 4000;

/// FNV-1a over UTF-16 code units: stable across runs, and what the ids were
/// made with before this was shared.
fn fnv(s: &str) -> String {
    let mut h: u32 = 0x811c9dc5;
    for c in s.encode_utf16() {
        h = (h ^ u32::from(c)).wrapping_mul(0x01000193);
    }
    format!("{h:08x}")
}

/// The id a server's tools are prefixed with: from its address, so it stays
/// the same across starts and when another server is removed.
pub fn server_id(url: &str) -> String {
    format!("mcp{}", fnv(url))
}

/// A tool's name as the model sees it: `[a-zA-Z0-9_-]`, at most 64, and two
/// servers may both have a `search`.
pub fn tool_name(server_id: &str, tool: &str) -> String {
    let n: String =
        format!("{server_id}__{tool}").chars().map(|c| if c.is_ascii_alphanumeric() || c == '_' || c == '-' { c } else { '_' }).collect();
    if n.len() <= MAX_NAME {
        return n;
    }
    format!("{}_{}", &n[..MAX_NAME - 9], fnv(tool))
}

/// [s] cut to [n] characters, `…` after a cut.
pub fn cap(s: &str, n: usize) -> String {
    match s.char_indices().nth(n) {
        Some((at, _)) => format!("{}…", &s[..at]),
        None => s.to_string(),
    }
}

/// A server's address without its scheme and path: what it is called until
/// it says.
pub fn host_of(url: &str) -> String {
    url.split_once("://").map_or(url, |(_, r)| r).split(['/', '?', '#']).next().unwrap_or(url).to_string()
}

/// What a server calls itself in its `initialize` answer [info] (its title,
/// else its name), else its address's host.
pub fn server_name(info: &Value, url: &str) -> String {
    info["serverInfo"]["title"]
        .as_str()
        .or(info["serverInfo"]["name"].as_str())
        .map(str::trim)
        .filter(|n| !n.is_empty())
        .map_or_else(|| host_of(url), String::from)
}

/// A server's instructions for the system prompt: trimmed, capped, None when
/// it says nothing.
pub fn server_instructions(text: Option<&str>) -> Option<String> {
    text.map(str::trim).filter(|s| !s.is_empty()).map(|s| cap(s, MAX_INSTRUCTIONS))
}

/// What servers say about using them, `(name, instructions)` each, for the
/// system prompt; None when none says anything.
pub fn instructions(servers: &[(String, String)]) -> Option<String> {
    let parts: Vec<String> = servers
        .iter()
        .filter_map(|(name, text)| server_instructions(Some(text)).map(|i| format!("## {name}\n\n{i}")))
        .collect();
    if parts.is_empty() {
        return None;
    }
    Some(format!("# MCP servers\n\nInstructions from the MCP servers whose tools you have:\n\n{}", parts.join("\n\n")))
}

/// A tool as the server lists it.
#[derive(Debug, Clone)]
pub struct McpTool {
    pub name: String,
    pub title: Option<String>,
    pub description: Option<String>,
    /// JSON Schema of the arguments.
    pub input_schema: Value,
    /// `annotations.readOnlyHint`: says it changes nothing. A hint from the
    /// server, not a guarantee.
    pub read_only: bool,
    /// `annotations.destructiveHint`, `true` unless said otherwise for a tool
    /// that is not read-only, as the specification has it.
    pub destructive: bool,
}

impl McpTool {
    /// One entry of a `tools/list` answer; None without a name.
    pub fn from_json(t: &Value) -> Option<Self> {
        let name = t["name"].as_str()?;
        let read_only = t["annotations"]["readOnlyHint"].as_bool() == Some(true);
        Some(Self {
            name: name.to_string(),
            title: t["title"].as_str().or(t["annotations"]["title"].as_str()).map(String::from),
            description: t["description"].as_str().map(String::from),
            input_schema: match &t["inputSchema"] {
                Value::Object(_) => t["inputSchema"].clone(),
                _ => json!({ "type": "object" }),
            },
            read_only,
            destructive: !read_only && t["annotations"]["destructiveHint"].as_bool() != Some(false),
        })
    }

    /// What the model is told it does: `[server] description`.
    pub fn description_for(&self, server: &str) -> String {
        let about = self.description.as_deref().or(self.title.as_deref()).unwrap_or("");
        format!("[{server}] {about}").trim().to_string()
    }

    /// `server · tool`, as a person reads it.
    pub fn label_for(&self, server: &str) -> String {
        format!("{server} · {}", self.title.as_deref().unwrap_or(&self.name))
    }
}

/// An MCP content part as pi content.
fn part(c: &Value) -> Value {
    let text = |t: String| json!({ "type": "text", "text": t });
    match c["type"].as_str() {
        Some("text") => text(c["text"].as_str().unwrap_or_default().to_string()),
        Some("image") => json!({ "type": "image", "data": c["data"], "mimeType": c["mimeType"] }),
        Some("audio") => text(format!("[Audio: {}, not shown]", c["mimeType"].as_str().unwrap_or("?"))),
        Some("resource") => {
            let r = &c["resource"];
            let uri = r["uri"].as_str().unwrap_or("?");
            match r["text"].as_str() {
                Some(t) => text(format!("[{uri}]\n{t}")),
                None => text(format!("[Resource: {uri}, binary, not shown]")),
            }
        }
        Some("resource_link") => {
            let name = c["title"].as_str().or(c["name"].as_str()).unwrap_or("link");
            let description = c["description"].as_str().map(|d| format!(" {d}")).unwrap_or_default();
            text(format!("[{name}]({}){description}", c["uri"].as_str().unwrap_or("")))
        }
        _ => text(c.to_string()),
    }
}

/// A `tools/call` answer [res] of [tool]: pi content and the structured
/// content as details, or the tool's own error text (`isError`).
pub fn call_result(tool: &str, res: &Value) -> Result<(Vec<Value>, Value), String> {
    let mut content: Vec<Value> = res["content"].as_array().into_iter().flatten().map(part).collect();
    if content.is_empty()
        && let Some(structured) = res.get("structuredContent").filter(|v| !v.is_null())
    {
        content.push(json!({ "type": "text", "text": structured.to_string() }));
    }
    if res["isError"].as_bool() == Some(true) {
        let text: Vec<&str> = content.iter().filter_map(|p| p["text"].as_str()).collect();
        return Err(if text.is_empty() { format!("{tool} failed") } else { text.join("\n") });
    }
    Ok((content, res.get("structuredContent").cloned().unwrap_or(Value::Null)))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_stay_what_they_were() {
        assert_eq!(fnv(""), "811c9dc5");
        assert_eq!(fnv("a"), "e40c292c");
        let long = "x".repeat(80);
        assert!(tool_name("mcp12345678", &long).ends_with(&format!("_{}", fnv(&long))));
        assert_eq!(tool_name("mcp1", "a.b c"), "mcp1__a_b_c");
        // What the Dart side made before this was shared, kept so stored
        // sessions name the same tools.
        assert_eq!(server_id("http://127.0.0.1:8123/api/mcp"), format!("mcp{}", fnv("http://127.0.0.1:8123/api/mcp")));
        assert_eq!(tool_name("mcp0a1b2c3d", "light.turn on"), "mcp0a1b2c3d__light_turn_on");
        let long = tool_name("mcp0a1b2c3d", &"x".repeat(80));
        assert_eq!(long.len(), 55 + 1 + 8);
        assert_eq!(tool_name("mcp0", "é"), "mcp0___");
    }

    #[test]
    fn tools_and_answers() {
        let t = McpTool::from_json(&json!({
            "name": "GetLiveContext", "description": "What is on.", "annotations": { "readOnlyHint": true, "title": "Live" }
        }))
        .unwrap();
        assert!(t.read_only && !t.destructive);
        assert_eq!(t.description_for("Home Assistant"), "[Home Assistant] What is on.");
        assert_eq!(t.label_for("Home Assistant"), "Home Assistant · Live");
        assert_eq!(t.input_schema, json!({ "type": "object" }));
        assert!(McpTool::from_json(&json!({ "name": "x" })).unwrap().destructive);
        assert!(McpTool::from_json(&json!({})).is_none());

        let (content, details) = call_result(
            "x",
            &json!({ "content": [
                { "type": "text", "text": "a" },
                { "type": "resource", "resource": { "uri": "file:///b", "text": "b" } },
                { "type": "resource_link", "uri": "https://c", "name": "c", "description": "C." },
            ], "structuredContent": { "ok": true } }),
        )
        .unwrap();
        let texts: Vec<&str> = content.iter().filter_map(|p| p["text"].as_str()).collect();
        assert_eq!(texts, ["a", "[file:///b]\nb", "[c](https://c) C."]);
        assert_eq!(details, json!({ "ok": true }));
        assert_eq!(call_result("x", &json!({ "structuredContent": { "n": 1 } })).unwrap().0[0]["text"], "{\"n\":1}");
        assert_eq!(call_result("x", &json!({ "content": [{ "type": "text", "text": "no" }], "isError": true })).unwrap_err(), "no");
        assert_eq!(call_result("x", &json!({ "content": [], "isError": true })).unwrap_err(), "x failed");

        assert_eq!(server_name(&json!({ "serverInfo": { "name": "hass", "title": " Home Assistant " } }), "http://h/mcp"), "Home Assistant");
        assert_eq!(server_name(&json!({}), "http://127.0.0.1:8123/api/mcp"), "127.0.0.1:8123");
        assert_eq!(instructions(&[("A".into(), "  ".into())]), None);
        let long = "x".repeat(MAX_INSTRUCTIONS + 1);
        assert!(instructions(&[("A".into(), long)]).unwrap().ends_with("x…"));
    }
}
