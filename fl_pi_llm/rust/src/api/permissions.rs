//! How an app's tool calls are approved (`crate::permissions`): JSON strings,
//! as the rest of the bridge. Permissions are `/agent/permissions`' shape
//! (`{defaultMode, disableBypass, rules, autoMode}`).

use flutter_rust_bridge::frb;
use serde_json::json;

use crate::permissions::{self as p, Decision, Effect, Judgment, Mode, Permissions};

fn parse(permissions: &str) -> anyhow::Result<Permissions> {
    Ok(serde_json::from_str(permissions)?)
}

/// What [command] is worth by its shape: `readOnly`, `unknown`, `caution` or
/// `destructive`.
#[frb(sync)]
pub fn permissions_classify(command: String) -> String {
    use p::risk::CommandRisk::*;
    match p::risk::classify(&command) {
        ReadOnly => "readOnly",
        Unknown => "unknown",
        Caution => "caution",
        Destructive => "destructive",
    }
    .into()
}

/// Why [permissions] cannot be stored; none when they can.
#[frb(sync)]
pub fn permissions_check(permissions: String) -> Option<String> {
    match parse(&permissions) {
        Ok(p) => p.check().err(),
        Err(e) => Some(e.to_string()),
    }
}

/// The built-in auto mode lists around [environment], as JSON.
#[frb(sync)]
pub fn permissions_defaults(environment: Vec<String>) -> String {
    p::defaults(environment).to_string()
}

/// What becomes of a call in [mode]: `{decision: run|ask|judge|deny, danger,
/// byRule, allowRule, message}`. [command] is the shell command it runs, none for a
/// tool that runs none; [claimed] `read`, `change` or `danger`, raised to the
/// command's shape.
#[frb(sync)]
pub fn permissions_decide(permissions: String, mode: String, command: Option<String>, claimed: String) -> anyhow::Result<String> {
    let perms = parse(&permissions)?;
    let claimed = Effect::parse(&claimed);
    let effect = command.as_deref().map_or(claimed, |c| Effect::of_command(claimed, c));
    Ok(match p::decide(&perms, Mode::parse(&mode), command.as_deref(), effect, false) {
        Decision::Deny { rule } => json!({ "decision": "deny", "rule": rule, "message": p::deny_message(&rule) }),
        Decision::Run => json!({ "decision": "run" }),
        Decision::Ask { danger, by_rule, allow_rule } => json!({ "decision": "ask", "danger": danger, "byRule": by_rule, "allowRule": allow_rule }),
        Decision::Judge => json!({ "decision": "judge" }),
    }
    .to_string())
}

/// The judge's instructions under [permissions], around [environment].
#[frb(sync)]
pub fn permissions_judge_prompt(permissions: String, environment: Vec<String>) -> anyhow::Result<String> {
    Ok(p::judge_prompt(&parse(&permissions)?.auto_mode, &p::defaults(environment)))
}

/// What the judge is shown: the person's words and the commands that ran
/// from [entries] (a session's entries, JSON), then [command].
#[frb(sync)]
pub fn permissions_judge_input(entries: String, command: String, title: String, claimed: String) -> String {
    let entries: Vec<serde_json::Value> = serde_json::from_str(&entries).unwrap_or_default();
    p::judge_input(&entries, &command, &title, &claimed, false)
}

/// The judge's answer, `{decision: allow|block, message}`; none when it said
/// nothing usable.
#[frb(sync)]
pub fn permissions_judgment(text: String) -> Option<String> {
    Some(
        match p::parse_judgment(&text)? {
            Judgment::Allow => json!({ "decision": "allow" }),
            Judgment::Block { rule, reason } => json!({ "decision": "block", "message": p::block_message(&rule, &reason) }),
        }
        .to_string(),
    )
}
