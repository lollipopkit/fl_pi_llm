//! Skills (`crate::skills`) for the apps, which fetch, unpack and keep them:
//! what a SKILL.md says, the skills among a source's files, where a source
//! is, the system prompt part and what the `skill` tool answers. JSON
//! strings, as the rest of the bridge; a skill is `{dir, name, description}`.

use flutter_rust_bridge::frb;
use serde_json::{Value, json};

use crate::skills::{self, Skill, SkillSource, Skills};

fn skills_of(json: &str) -> anyhow::Result<Vec<Skill>> {
    let v: Vec<Value> = serde_json::from_str(json)?;
    Ok(v.iter()
        .filter_map(|s| {
            Some(Skill {
                dir: s["dir"].as_str()?.to_string(),
                name: s["name"].as_str()?.to_string(),
                description: s["description"].as_str().unwrap_or_default().to_string(),
            })
        })
        .collect())
}

/// [md]'s front matter: `{name, description, body}`, or None unless it names
/// the skill and says what it is for.
#[frb(sync)]
pub fn skill_parse(md: String) -> Option<String> {
    skills::parse(&md).map(|m| json!({ "name": m.name, "description": m.description, "body": m.body }).to_string())
}

/// A skill's directory name, as the `skills` CLI makes it.
#[frb(sync)]
pub fn skill_dir_name(name: String) -> String {
    skills::dir_name(&name)
}

/// Whether [path] in a source is a SKILL.md: the files [skill_find] needs
/// the text of.
#[frb(sync)]
pub fn skill_is_md(path: String) -> bool {
    skills::is_skill_md(&path)
}

/// The skills among a source's [paths], under [path] when given, [mds] the
/// text of its SKILL.md files by path (`{path: text}`): `[{name,
/// description, dir, files: [[path in the skill, path in the source]]}]`.
#[frb(sync)]
pub fn skill_find(paths: Vec<String>, mds: String, path: Option<String>) -> anyhow::Result<String> {
    let mds: serde_json::Map<String, Value> = serde_json::from_str(&mds)?;
    let found = skills::find_paths(paths.iter().map(String::as_str), |p| mds.get(p)?.as_str().map(String::from), path.as_deref());
    let out: Vec<Value> = found
        .into_iter()
        .map(|f| json!({ "name": f.name, "description": f.description, "dir": f.dir, "files": f.files }))
        .collect();
    Ok(Value::Array(out).to_string())
}

/// What the user typed or pasted as a source: `{ok: true, source, skill?}`
/// (the source as a lock keeps it, `{type, …}`), or `{ok: false, error}`.
#[frb(sync)]
pub fn skill_source_parse(input: String) -> String {
    match SkillSource::parse(&input) {
        Ok(s) => {
            let mut v = s.to_json();
            v["ok"] = json!(true);
            v
        }
        Err(error) => json!({ "ok": false, "error": error }),
    }
    .to_string()
}

/// The `skill` tool: `{name, description, parameters}`.
#[frb(sync)]
pub fn skill_tool() -> String {
    json!({ "name": skills::TOOL_NAME, "description": skills::TOOL_DESCRIPTION, "parameters": skills::tool_parameters() }).to_string()
}

/// The skills part of the system prompt over [offered], in that order.
#[frb(sync)]
pub fn skill_prompt(offered: String) -> anyhow::Result<Option<String>> {
    Ok(skills::prompt(&skills_of(&offered)?))
}

/// What the `skill` tool answers for [args] (JSON) over the skills in
/// [root], offering [offered]: `{ok: true, text}`, or `{ok: false, error}`,
/// told to the model as it is.
#[frb(sync)]
pub fn skill_run(root: String, offered: String, args: String) -> anyhow::Result<String> {
    let args: Value = serde_json::from_str(&args)?;
    Ok(match Skills::new(root).run_tool(&skills_of(&offered)?, &args) {
        Ok(text) => json!({ "ok": true, "text": text }),
        Err(error) => json!({ "ok": false, "error": error }),
    }
    .to_string())
}

/// [file] of skill [dir] in [root] as text; None when there is no such text
/// file in it.
#[frb(sync)]
pub fn skill_read(root: String, dir: String, file: String) -> Option<String> {
    Skills::new(root).read(&dir, &file)
}

/// The files of skill [dir] in [root], SKILL.md first.
#[frb(sync)]
pub fn skill_files(root: String, dir: String) -> Vec<String> {
    Skills::new(root).files_of(&dir)
}
