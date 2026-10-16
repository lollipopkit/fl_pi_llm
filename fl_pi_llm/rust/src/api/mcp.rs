//! MCP tools (`crate::mcp`) for the apps, whose client (mcp_dart) connects
//! and signs in: what a server's tools are called and say, its instructions
//! and a call's answer. JSON strings, as the rest of the bridge.

use flutter_rust_bridge::frb;
use serde_json::{Value, json};

use crate::mcp::{self, McpTool};

/// The id a server's tools are prefixed with, from its [url].
#[frb(sync)]
pub fn mcp_server_id(url: String) -> String {
    mcp::server_id(&url)
}

/// What a server calls itself in its `initialize` answer [info] (JSON),
/// else [url]'s host.
#[frb(sync)]
pub fn mcp_server_name(info: String, url: String) -> anyhow::Result<String> {
    Ok(mcp::server_name(&serde_json::from_str(&info)?, &url))
}

/// [tool] (one entry of `tools/list`, JSON) of server [server_id], called
/// [server]: `{name, description, label, parameters, title, readOnly,
/// destructive}`, or None without a name.
#[frb(sync)]
pub fn mcp_tool(server_id: String, server: String, tool: String) -> anyhow::Result<Option<String>> {
    let Some(t) = McpTool::from_json(&serde_json::from_str(&tool)?) else { return Ok(None) };
    Ok(Some(
        json!({
            "name": mcp::tool_name(&server_id, &t.name),
            "description": t.description_for(&server),
            "label": t.label_for(&server),
            "parameters": t.input_schema,
            "title": t.title.as_deref().unwrap_or(&t.name),
            "readOnly": t.read_only,
            "destructive": t.destructive,
        })
        .to_string(),
    ))
}

/// What [servers] (`[[name, instructions]]`) say about using them, for the
/// system prompt.
#[frb(sync)]
pub fn mcp_instructions(servers: String) -> anyhow::Result<Option<String>> {
    Ok(mcp::instructions(&serde_json::from_str::<Vec<(String, String)>>(&servers)?))
}

/// [tool]'s `tools/call` answer [result] (JSON): `{ok: true, content,
/// details}` as pi content, or `{ok: false, error}`, the tool's own error.
#[frb(sync)]
pub fn mcp_call_result(tool: String, result: String) -> anyhow::Result<String> {
    let result: Value = serde_json::from_str(&result)?;
    Ok(match mcp::call_result(&tool, &result) {
        Ok((content, details)) => json!({ "ok": true, "content": content, "details": details }),
        Err(error) => json!({ "ok": false, "error": error }),
    }
    .to_string())
}
