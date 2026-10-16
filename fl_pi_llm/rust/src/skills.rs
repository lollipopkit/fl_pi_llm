//! Skills: folders holding a `SKILL.md` (front matter with a `name` and a
//! `description`, then instructions) and whatever files it points to, in one
//! directory the host keeps. The one implementation of what a skill is, for
//! the apps (`api::skills`, over the bridge) and a Rust host (`host::skills`):
//! reading a SKILL.md, finding skills among a source's files the way the
//! `skills` CLI does, reading where a source is, the system prompt part and
//! what the `skill` tool answers.
//!
//! Fetching a source, unpacking it and keeping what is installed are the
//! host's.

use std::collections::{BTreeMap, BTreeSet};
use std::path::{Component, Path, PathBuf};

use serde_json::{Value, json};
use yaml_rust2::{Yaml, YamlLoader};

/// The tool's name.
pub const TOOL_NAME: &str = "skill";
/// What the tool says it does.
pub const TOOL_DESCRIPTION: &str =
    "Load an installed skill: its instructions (SKILL.md) and the list of its files, or one of those files.";
/// What one read of a file gives the model, at most.
pub const MAX_READ_CHARS: usize = 256 * 1024;
/// What the prompt carries of a description.
const MAX_DESCRIPTION: usize = 1024;
/// Files listed of one skill, at most.
const MAX_FILES: usize = 200;

/// The tool's arguments, as JSON Schema.
pub fn tool_parameters() -> Value {
    json!({
        "type": "object",
        "properties": {
            "name": { "type": "string", "description": "The skill, as the list of available skills names it." },
            "file": {
                "type": "string",
                "description": "A file of the skill, by its path relative to the skill. Default: SKILL.md, with the list of its files.",
            },
        },
        "required": ["name"],
    })
}

/// A skill on this device.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Skill {
    /// Its directory's name: what the model asks for it by.
    pub dir: String,
    pub name: String,
    pub description: String,
}

/// A SKILL.md's front matter and the instructions after it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillMd {
    pub name: String,
    pub description: String,
    pub body: String,
}

/// One line of text: no control characters, no escape sequences.
pub fn clean(s: &str) -> String {
    static ESC: std::sync::LazyLock<regex::Regex> =
        std::sync::LazyLock::new(|| regex::Regex::new(r"\x1B\[[0-9;?]*[ -/]*[@-~]").expect("regex"));
    let s = ESC.replace_all(s, "");
    let mut out = String::with_capacity(s.len());
    let mut space = false;
    for c in s.chars() {
        if matches!(c, '\r' | '\n' | '\t') {
            space = true;
            continue;
        }
        if c.is_control() {
            continue;
        }
        if space && !out.is_empty() {
            out.push(' ');
        }
        space = false;
        out.push(c);
    }
    out.trim().to_string()
}

/// [md]'s front matter: None unless it names the skill and says what it is
/// for, both as text. The closing `---` is a line of its own.
pub fn parse(md: &str) -> Option<SkillMd> {
    let md = md.strip_prefix('\u{feff}').unwrap_or(md).replace("\r\n", "\n");
    let rest = md.strip_prefix("---\n")?;
    let at = rest.find("\n---")?;
    let after = &rest[at + 4..];
    if !(after.is_empty() || after.starts_with('\n')) {
        return None;
    }
    let (front, body) = (&rest[..at], after.strip_prefix('\n').unwrap_or(after));
    let docs = YamlLoader::load_from_str(front).ok()?;
    let doc = docs.first()?;
    let (Yaml::String(name), Yaml::String(description)) = (&doc["name"], &doc["description"]) else { return None };
    let (name, description) = (clean(name), clean(description));
    if name.is_empty() || description.is_empty() {
        return None;
    }
    Some(SkillMd { name, description, body: body.to_string() })
}

/// [rel] resolved under [base], or None when it would leave it.
fn inside(base: &Path, rel: &str) -> Option<PathBuf> {
    let rel = Path::new(rel);
    if rel.is_absolute() {
        return None;
    }
    let mut out = base.to_path_buf();
    for c in rel.components() {
        match c {
            Component::Normal(p) => out.push(p),
            Component::CurDir => {}
            _ => return None,
        }
    }
    (out != base).then_some(out)
}

/// The skills in one directory: `<root>/<dir>/SKILL.md`.
#[derive(Debug, Clone)]
pub struct Skills {
    root: PathBuf,
}

impl Skills {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    /// Every skill there, by directory name; a folder without a readable
    /// SKILL.md is not one, nor one whose name starts with a dot.
    pub fn list(&self) -> Vec<Skill> {
        let Ok(entries) = std::fs::read_dir(&self.root) else { return Vec::new() };
        let mut out: Vec<Skill> = entries
            .flatten()
            .filter(|e| e.file_type().is_ok_and(|t| t.is_dir()))
            .filter_map(|e| {
                let dir = e.file_name().to_string_lossy().into_owned();
                if dir.starts_with('.') {
                    return None;
                }
                let md = parse(&std::fs::read_to_string(e.path().join("SKILL.md")).ok()?)?;
                Some(Skill { dir, name: md.name, description: md.description })
            })
            .collect();
        out.sort_by(|a, b| a.dir.cmp(&b.dir));
        out
    }

    /// [file] of skill [dir] as text; None when there is no such text file
    /// in it. A link out of the skill's folder is not in it.
    pub fn read(&self, dir: &str, file: &str) -> Option<String> {
        let base = inside(&self.root, dir)?;
        let path = inside(&base, file)?;
        let real = std::fs::canonicalize(&path).ok()?;
        if !real.starts_with(std::fs::canonicalize(&base).ok()?) {
            return None;
        }
        String::from_utf8(std::fs::read(real).ok()?).ok()
    }

    /// The files of skill [dir], SKILL.md first, by path relative to it;
    /// links are not followed.
    pub fn files_of(&self, dir: &str) -> Vec<String> {
        let Some(base) = inside(&self.root, dir) else { return Vec::new() };
        let mut files = Vec::new();
        let mut stack = vec![base.clone()];
        while let Some(d) = stack.pop() {
            for e in std::fs::read_dir(&d).into_iter().flatten().flatten() {
                let Ok(t) = e.file_type() else { continue };
                if t.is_dir() {
                    stack.push(e.path());
                } else if t.is_file()
                    && let Ok(rel) = e.path().strip_prefix(&base)
                {
                    files.push(rel.to_string_lossy().replace('\\', "/"));
                }
            }
        }
        files.sort();
        if let Some(at) = files.iter().position(|f| f == "SKILL.md") {
            let md = files.remove(at);
            files.insert(0, md);
        }
        files
    }

    /// What the `skill` tool answers for [args] (`{name, file?}`), offering
    /// only [offered]: the SKILL.md with the list of the skill's other files,
    /// or the one file asked for. Err is what the model is told instead.
    pub fn run_tool(&self, offered: &[Skill], args: &Value) -> Result<String, String> {
        let name = args["name"].as_str().ok_or("name is required")?;
        let skill = offered.iter().find(|s| s.dir == name).or_else(|| offered.iter().find(|s| s.name == name));
        let Some(skill) = skill else {
            let names: Vec<&str> = offered.iter().map(|s| s.dir.as_str()).collect();
            return Err(format!("No skill \"{name}\". Available: {}", names.join(", ")));
        };
        let file = args["file"].as_str().filter(|f| !f.is_empty());
        let text = self
            .read(&skill.dir, file.unwrap_or("SKILL.md"))
            .ok_or_else(|| format!("No text file \"{}\" in {}", file.unwrap_or("SKILL.md"), skill.dir))?;
        let body = match text.char_indices().nth(MAX_READ_CHARS) {
            Some((at, _)) => format!("{}\n… (truncated)", &text[..at]),
            None => text,
        };
        if file.is_some() {
            return Ok(body);
        }
        let others: Vec<String> =
            self.files_of(&skill.dir).into_iter().filter(|f| f != "SKILL.md").take(MAX_FILES).map(|f| format!("- {f}")).collect();
        Ok(if others.is_empty() { body } else { format!("{body}\n\nFiles of this skill (read one with `file`):\n{}", others.join("\n")) })
    }
}

/// The skills part of the system prompt for [skills], in their order: what
/// each is for, the model to load one with the `skill` tool when a task
/// matches it. None without any.
pub fn prompt(skills: &[Skill]) -> Option<String> {
    if skills.is_empty() {
        return None;
    }
    let list: Vec<String> = skills
        .iter()
        .map(|s| {
            let d = match s.description.char_indices().nth(MAX_DESCRIPTION) {
                Some((at, _)) => format!("{}…", &s.description[..at]),
                None => s.description.clone(),
            };
            format!("- {}: {d}", s.dir)
        })
        .collect();
    Some(format!(
        "# Skills\n\nSkills are instructions for particular tasks that the user installed. When a task matches a skill's \
description, load the skill with the `{TOOL_NAME}` tool before starting the task, and follow it. A skill may point to its \
other files by relative path; read those with the same tool when you need them. Scripts in a skill cannot run here unless \
another tool can run them.\n\nAvailable skills:\n{}",
        list.join("\n")
    ))
}

/// A skill's directory name, as the `skills` CLI makes it (`sanitizeName`).
pub fn dir_name(name: &str) -> String {
    static NOT: std::sync::LazyLock<regex::Regex> = std::sync::LazyLock::new(|| regex::Regex::new(r"[^a-z0-9._]+").expect("regex"));
    let s = NOT.replace_all(&name.to_lowercase(), "-").into_owned();
    let s = s.trim_matches(|c| c == '.' || c == '-');
    let s: String = s.chars().take(255).collect();
    if s.is_empty() { "unnamed-skill".into() } else { s }
}

/// A skill found among a source's files, by path: its files as `(path
/// relative to the skill, path in the source)`, `SKILL.md` by that name
/// whatever its case in the source.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Found {
    pub name: String,
    pub description: String,
    /// Its folder in the source; empty for the source's root.
    pub dir: String,
    pub files: Vec<(String, String)>,
}

/// A skill found among a source's files, with them.
#[derive(Debug, Clone)]
pub struct FoundSkill {
    pub name: String,
    pub description: String,
    pub dir: String,
    pub files: BTreeMap<String, Vec<u8>>,
}

/// Where agents keep skills in a repository, looked in below the root.
const CONTAINERS: &[&str] = &[
    "skills", "skills/.curated", "skills/.experimental", "skills/.system", ".agents/skills", ".claude/skills", ".cline/skills",
    ".codebuddy/skills", ".codex/skills", ".commandcode/skills", ".continue/skills", ".factory/skills", ".github/skills",
    ".goose/skills", ".grok/skills", ".iflow/skills", ".junie/skills", ".kilo/skills", ".kilocode/skills", ".kimchi/skills",
    ".kiro/skills", ".minimax/skills", ".mux/skills", ".neovate/skills", ".opencode/skills", ".openhands/skills", ".pi/skills",
    ".posit/assistant/skills", ".qoder/skills", ".roo/skills", ".trae/skills", ".windsurf/skills", ".zcode/skills",
    ".zencoder/skills",
];
const CONTAINER_DEPTH: usize = 3;
const FALLBACK_DEPTH: usize = 5;
const SKIP_DIRS: &[&str] = &["node_modules", ".git", "dist", "build", "__pycache__"];
const SKIP_FILES: &[&str] = &["metadata.json"];
const SKIP_FILE_DIRS: &[&str] = &[".git", "__pycache__", "__pypackages__"];

/// Whether [path] (in a source) is a SKILL.md, whatever its case: the files
/// [find_paths] needs the text of.
pub fn is_skill_md(path: &str) -> bool {
    path.rsplit('/').next().is_some_and(|n| n.eq_ignore_ascii_case("skill.md"))
}

/// The skills among a source's [paths], under [path] when given, the way the
/// `skills` CLI finds them (`src/skills.ts`): a SKILL.md there is the one
/// skill; otherwise the usual places, and every folder below them that has a
/// SKILL.md, without looking inside one that does; and when those have none,
/// anywhere a few levels down. The first of a name wins. [md] gives a
/// SKILL.md's text by its path.
pub fn find_paths<'a>(paths: impl IntoIterator<Item = &'a str>, md: impl Fn(&str) -> Option<String>, path: Option<&str>) -> Vec<Found> {
    let base = path.filter(|p| !p.is_empty()).map(|p| format!("{p}/")).unwrap_or_default();
    let paths: Vec<&str> = paths.into_iter().filter(|p| p.starts_with(&base)).collect();
    let mut skill_dirs = BTreeSet::new();
    for p in &paths {
        if is_skill_md(p) {
            skill_dirs.insert(p.rsplit_once('/').map_or("", |(d, _)| d).to_string());
        }
    }
    let root = base.strip_suffix('/').unwrap_or("").to_string();
    let mut found: Vec<Found> = Vec::new();
    let mut seen = BTreeSet::new();
    let mut add = |dir: &str, found: &mut Vec<Found>| {
        if let Some(s) = load(&paths, &md, dir)
            && seen.insert(s.name.clone())
        {
            found.push(s);
        }
    };
    if skill_dirs.contains(&root) {
        add(&root, &mut found);
        if !found.is_empty() {
            return found;
        }
    }
    // Folders below [dir] with a SKILL.md, not below one that has it.
    let walk = |dir: &str, depth: usize| -> Vec<String> {
        let prefix = if dir.is_empty() { String::new() } else { format!("{dir}/") };
        let mut out: Vec<String> = skill_dirs
            .iter()
            .filter(|d| d.as_str() != dir && d.starts_with(&prefix))
            .filter(|d| {
                let rel: Vec<&str> = d[prefix.len()..].split('/').collect();
                rel.len() <= depth
                    && !rel.iter().any(|p| SKIP_DIRS.contains(p))
                    && !(1..rel.len()).any(|i| skill_dirs.contains(&format!("{prefix}{}", rel[..i].join("/"))))
            })
            .cloned()
            .collect();
        out.sort();
        out
    };
    for d in walk(&root, 1) {
        add(&d, &mut found);
    }
    for c in CONTAINERS {
        let at = if root.is_empty() { c.to_string() } else { format!("{root}/{c}") };
        for d in walk(&at, CONTAINER_DEPTH) {
            add(&d, &mut found);
        }
    }
    if found.is_empty() {
        for d in walk(&root, FALLBACK_DEPTH) {
            add(&d, &mut found);
        }
    }
    found
}

fn load(paths: &[&str], md: &impl Fn(&str) -> Option<String>, dir: &str) -> Option<Found> {
    let prefix = if dir.is_empty() { String::new() } else { format!("{dir}/") };
    let md_key = *paths.iter().find(|k| k.starts_with(&prefix) && k[prefix.len()..].eq_ignore_ascii_case("skill.md"))?;
    let parsed = parse(&md(md_key)?)?;
    let keeps = |rel: &str| {
        let parts: Vec<&str> = rel.split('/').collect();
        !SKIP_FILES.contains(parts.last().unwrap_or(&"")) && !parts[..parts.len() - 1].iter().any(|p| SKIP_FILE_DIRS.contains(p))
    };
    let mut files: Vec<(String, String)> = paths
        .iter()
        .filter(|k| k.starts_with(&prefix) && keeps(&k[prefix.len()..]))
        .map(|k| (if *k == md_key { "SKILL.md".to_string() } else { k[prefix.len()..].to_string() }, k.to_string()))
        .collect();
    files.sort();
    Some(Found { name: parsed.name, description: parsed.description, dir: dir.to_string(), files })
}

/// [find_paths] over a source's [files] themselves.
pub fn find(files: &BTreeMap<String, Vec<u8>>, path: Option<&str>) -> Vec<FoundSkill> {
    find_paths(files.keys().map(String::as_str), |p| files.get(p).map(|b| String::from_utf8_lossy(b).into_owned()), path)
        .into_iter()
        .map(|f| FoundSkill {
            name: f.name,
            description: f.description,
            dir: f.dir,
            files: f.files.into_iter().filter_map(|(rel, key)| Some((rel, files.get(&key)?.clone()))).collect(),
        })
        .collect()
}

/// Where skills are installed from, as `npx skills add` takes it (the
/// `skills` CLI's `src/source-parser.ts`, minus what needs git itself: ssh,
/// Azure Repos, GitHub Enterprise), and the one skill wanted of several.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkillSource {
    pub at: Source,
    /// By name: `owner/repo@skill`, `#ref@skill` or `--skill`. None for all
    /// of them, to choose from.
    pub skill: Option<String>,
}

/// Where a source is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Source {
    /// A repository on GitHub, its archive of `ref` (the default branch when
    /// None), looked in under `path`.
    GitHub { owner: String, repo: String, r#ref: Option<String>, path: Option<String> },
    /// A project on GitLab or a GitLab instance (`https://gitlab.com/group/sub/repo`).
    GitLab { project: String, r#ref: Option<String>, path: Option<String> },
    /// A file: a lone SKILL.md, or an archive of skills.
    Download { url: String },
    /// A site that may publish its skills in a `/.well-known` index.
    Site { url: String },
    /// A folder, an archive or a SKILL.md on this device.
    Local { path: String },
    /// A skill the app ships.
    Builtin,
}

impl Source {
    /// What a lock keeps of it (no skill): `{type, …}`.
    pub fn to_json(&self) -> Value {
        let mut v = match self {
            Self::GitHub { owner, repo, .. } => json!({ "type": "github", "owner": owner, "repo": repo }),
            Self::GitLab { project, .. } => json!({ "type": "gitlab", "project": project }),
            Self::Download { url } => json!({ "type": "download", "url": url }),
            Self::Site { url } => json!({ "type": "site", "url": url }),
            Self::Local { path } => json!({ "type": "local", "path": path }),
            Self::Builtin => json!({ "type": "builtin" }),
        };
        if let Self::GitHub { r#ref, path, .. } | Self::GitLab { r#ref, path, .. } = self {
            if let Some(r) = r#ref {
                v["ref"] = json!(r);
            }
            if let Some(p) = path {
                v["path"] = json!(p);
            }
        }
        v
    }

    /// `owner/repo`, the project, the address or the path: as a person reads it.
    pub fn id(&self) -> String {
        match self {
            Self::GitHub { owner, repo, .. } => format!("{owner}/{repo}"),
            Self::GitLab { project, .. } => project.clone(),
            Self::Download { url } | Self::Site { url } => url.clone(),
            Self::Local { path } => path.clone(),
            Self::Builtin => "builtin".into(),
        }
    }
}

impl SkillSource {
    /// Reads what the user typed or pasted: a source, or a whole `npx skills
    /// add <source> [--skill <name>]` line.
    pub fn parse(input: &str) -> Result<Self, String> {
        let words: Vec<&str> = input.split_whitespace().collect();
        let words = match words.iter().position(|w| *w == "add") {
            Some(add) if add > 0 && words[add - 1] == "skills" => &words[add + 1..],
            _ => &words[..],
        };
        let (mut skill, mut source) = (None, None);
        let mut i = 0;
        while i < words.len() {
            let w = words[i];
            if (w == "--skill" || w == "-s") && i + 1 < words.len() {
                i += 1;
                skill = Some(words[i].to_string());
            } else if let Some(s) = w.strip_prefix("--skill=") {
                skill = Some(s.to_string());
            } else if !w.starts_with('-') && source.is_none() {
                // Where to install, `-y`, `-g`…: the CLI's, not ours.
                source = Some(w);
            }
            i += 1;
        }
        let mut parsed = Self::parse_one(source.ok_or("no source")?)?;
        if let Some(s) = skill.filter(|s| s != "*") {
            parsed.skill = Some(s);
        }
        Ok(parsed)
    }

    fn parse_one(input: &str) -> Result<Self, String> {
        // A folder or a file on this device: absolute, `~/`, or `C:\`.
        let b = input.as_bytes();
        if input.starts_with('/') || input.starts_with("~/") || (b.len() > 2 && b[0].is_ascii_alphabetic() && b[1] == b':' && matches!(b[2], b'\\' | b'/')) {
            return Ok(Self { at: Source::Local { path: input.into() }, skill: None });
        }
        // `#ref` or `#ref@skill`, on what looks like a repository.
        let (mut s, mut r#ref, mut frag_skill) = (input.to_string(), None, None);
        if let Some(hash) = s.find('#').filter(|h| *h > 0) {
            let frag = percent_decode(&s[hash + 1..]);
            s.truncate(hash);
            let (r, k) = frag.split_once('@').map_or((frag.as_str(), None), |(r, k)| (r, Some(k.to_string())));
            r#ref = Some(r.to_string()).filter(|r| !r.is_empty());
            frag_skill = k;
        }
        let frag = |r: &Option<String>, k: &Option<String>| match (r, k) {
            (None, None) => String::new(),
            _ => format!("#{}{}", r.as_deref().unwrap_or(""), k.as_ref().map(|k| format!("@{k}")).unwrap_or_default()),
        };
        if let Some(rest) = s.strip_prefix("github:") {
            return Self::parse_one(&format!("{rest}{}", frag(&r#ref, &frag_skill)));
        }
        if let Some(rest) = s.strip_prefix("gitlab:") {
            return Self::parse_one(&format!("https://gitlab.com/{rest}{}", frag(&r#ref, &frag_skill)));
        }
        if let Some(url) = Url::parse(&s) {
            return Self::parse_url(&url, r#ref, frag_skill);
        }
        static AT_SKILL: std::sync::LazyLock<regex::Regex> =
            std::sync::LazyLock::new(|| regex::Regex::new(r"^([^/:.][^/:]*)/([^/@:]+)@(.+)$").expect("regex"));
        static SHORT: std::sync::LazyLock<regex::Regex> =
            std::sync::LazyLock::new(|| regex::Regex::new(r"^([^/:.][^/:]*)/([^/:]+?)(?:/(.+?))?/?$").expect("regex"));
        if let Some(c) = AT_SKILL.captures(&s) {
            let at = Source::GitHub { owner: c[1].into(), repo: repo(&c[2]), r#ref, path: None };
            return Ok(Self { at, skill: frag_skill.or(Some(c[3].into())) });
        }
        if let Some(c) = SHORT.captures(&s) {
            let path = match c.get(3) {
                Some(p) => subpath(p.as_str())?,
                None => None,
            };
            return Ok(Self { at: Source::GitHub { owner: c[1].into(), repo: repo(&c[2]), r#ref, path }, skill: frag_skill });
        }
        Err("not a skill source".into())
    }

    fn parse_url(u: &Url, r#ref: Option<String>, skill: Option<String>) -> Result<Self, String> {
        let host = u.host.to_ascii_lowercase();
        let segs: Vec<&str> = u.path.split('/').filter(|e| !e.is_empty()).collect();
        let with = |at: Source| Ok(Self { at, skill: skill.clone() });

        // A file to download: an archive, a release asset, a raw SKILL.md.
        let download = match host.as_str() {
            "raw.githubusercontent.com" | "codeload.github.com" | "objects.githubusercontent.com" => true,
            "github.com" => segs.len() > 2 && matches!(segs[2], "archive" | "raw" | "releases"),
            "gitlab.com" => u.path.contains("/-/archive/") || u.path.contains("/-/raw/"),
            _ => false,
        };
        if download {
            return with(Source::Download { url: u.whole.clone() });
        }
        if host == "github.com" || host == "www.github.com" {
            if segs.len() < 2 {
                return Err("not a repository".into());
            }
            let (owner, name) = (segs[0].to_string(), repo(segs[1]));
            // `/tree/<ref>/<path>` or `/blob/<ref>/<path>/SKILL.md`: a ref of
            // one segment, as the CLI takes it.
            if segs.len() >= 4 && (segs[2] == "tree" || segs[2] == "blob") {
                let mut rest = segs[4..].to_vec();
                if segs[2] == "blob" && rest.last().is_some_and(|l| l.eq_ignore_ascii_case("skill.md")) {
                    rest.pop();
                }
                return with(Source::GitHub { owner, repo: name, r#ref: Some(segs[3].into()), path: subpath(&rest.join("/"))? });
            }
            return with(Source::GitHub { owner, repo: name, r#ref, path: None });
        }
        if host == "gitlab.com" || u.path.contains("/-/tree/") {
            if let Some(tree) = segs.iter().position(|s| *s == "-")
                && tree > 0
                && segs.len() > tree + 2
                && segs[tree + 1] == "tree"
            {
                return with(Source::GitLab {
                    project: u.at(&segs[..tree].join("/")),
                    r#ref: Some(segs[tree + 2].into()),
                    path: subpath(&segs[tree + 3..].join("/"))?,
                });
            }
            if host == "gitlab.com" && segs.len() >= 2 {
                let mut parts: Vec<String> = segs.iter().map(|s| s.to_string()).collect();
                let last = parts.pop().map(|l| repo(&l)).unwrap_or_default();
                parts.push(last);
                return with(Source::GitLab { project: u.at(&parts.join("/")), r#ref, path: None });
            }
        }
        // A site: its `/.well-known` index, else the file itself.
        with(Source::Site { url: u.whole.clone() })
    }

    /// `{source, skill?}`: [Source::to_json] and the one skill wanted.
    pub fn to_json(&self) -> Value {
        let mut v = json!({ "source": self.at.to_json() });
        if let Some(s) = &self.skill {
            v["skill"] = json!(s);
        }
        v
    }
}

fn repo(r: &str) -> String {
    r.strip_suffix(".git").unwrap_or(r).to_string()
}

/// A path inside the source, which may not climb out of it.
fn subpath(p: &str) -> Result<Option<String>, String> {
    let parts: Vec<&str> = p.split(['/', '\\']).filter(|e| !e.is_empty() && *e != ".").collect();
    if parts.contains(&"..") {
        return Err("a path out of the source".into());
    }
    Ok((!parts.is_empty()).then(|| parts.join("/")))
}

/// `%XX` decoded; anything not a valid escape or UTF-8 is kept as it is.
fn percent_decode(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%'
            && i + 2 < b.len()
            && let Some(v) = std::str::from_utf8(&b[i + 1..i + 3]).ok().and_then(|h| u8::from_str_radix(h, 16).ok())
        {
            out.push(v);
            i += 3;
        } else {
            out.push(b[i]);
            i += 1;
        }
    }
    String::from_utf8(out).unwrap_or_else(|_| s.to_string())
}

/// An `http(s)://` address, as much of it as a source needs.
struct Url {
    /// What was given, the fragment already taken off.
    whole: String,
    /// `scheme://host[:port]`.
    origin: String,
    host: String,
    path: String,
}

impl Url {
    fn parse(s: &str) -> Option<Self> {
        let (scheme, rest) = s.split_once("://")?;
        if !scheme.eq_ignore_ascii_case("https") && !scheme.eq_ignore_ascii_case("http") {
            return None;
        }
        let end = rest.find(['/', '?']).unwrap_or(rest.len());
        let authority = &rest[..end];
        let host_port = authority.rsplit_once('@').map_or(authority, |(_, h)| h);
        let host = host_port.split(':').next().unwrap_or("");
        if host.is_empty() {
            return None;
        }
        let path = rest[end..].split('?').next().unwrap_or("");
        Some(Self { whole: s.to_string(), origin: format!("{}://{host_port}", scheme.to_ascii_lowercase()), host: host.into(), path: path.into() })
    }

    /// [path] on this origin, and nothing else of it.
    fn at(&self, path: &str) -> String {
        format!("{}/{path}", self.origin)
    }
}

/// A GitHub repository, what a host that installs only from GitHub reads a
/// source as (`codeload.github.com` archives).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GitHubSource {
    pub owner: String,
    pub repo: String,
    pub r#ref: Option<String>,
    pub path: Option<String>,
    /// The one skill wanted of several; None for all of them.
    pub skill: Option<String>,
}

impl GitHubSource {
    /// [SkillSource::parse], refusing every source but a GitHub repository.
    pub fn parse(input: &str) -> Result<Self, String> {
        match SkillSource::parse(input)? {
            SkillSource { at: Source::GitHub { owner, repo, r#ref, path }, skill } => Ok(Self { owner, repo, r#ref, path, skill }),
            _ => Err("only GitHub repositories".into()),
        }
    }

    /// Where its archive is: GitHub's own download host, which answers
    /// without a redirect.
    pub fn archive_url(&self) -> String {
        format!("https://codeload.github.com/{}/{}/tar.gz/{}", self.owner, self.repo, self.r#ref.as_deref().unwrap_or("HEAD"))
    }

    /// `owner/repo[/path]`, as a person reads it.
    pub fn id(&self) -> String {
        let mut id = format!("{}/{}", self.owner, self.repo);
        if let Some(p) = &self.path {
            id = format!("{id}/{p}");
        }
        id
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn front_matter() {
        let md = "\u{feff}---\r\nname: Docker cleanup\r\ndescription: >\r\n  Frees disk space\r\n  safely.\r\n---\r\n# Steps\n";
        assert_eq!(
            parse(md),
            Some(SkillMd { name: "Docker cleanup".into(), description: "Frees disk space safely.".into(), body: "# Steps\n".into() })
        );
        assert_eq!(parse("---\nname: a\n---\n"), None, "no description");
        assert_eq!(parse("---\nname: a\ndescription: [1]\n---\n"), None, "not text");
        assert_eq!(parse("---\nname: a\ndescription: b\n--- trailing\n"), None, "the closing line is `---` alone");
        assert_eq!(parse("# no front matter"), None);
        assert_eq!(clean("a\u{1b}[31m red\u{1b}[0m\n\tb\u{7}\u{85}"), "a red b");
    }

    fn src(input: &str) -> SkillSource {
        SkillSource::parse(input).unwrap_or_else(|e| panic!("{input}: {e}"))
    }

    fn gh(owner: &str, repo: &str, r: Option<&str>, path: Option<&str>) -> Source {
        Source::GitHub { owner: owner.into(), repo: repo.into(), r#ref: r.map(String::from), path: path.map(String::from) }
    }

    #[test]
    fn sources_read_as_the_cli_reads_them() {
        assert_eq!(src("anthropics/skills").at, gh("anthropics", "skills", None, None));
        assert_eq!(src("npx skills add owner/repo.git/skills/pdf -y").at, gh("owner", "repo", None, Some("skills/pdf")));
        let s = src("owner/repo@pdf");
        assert_eq!((s.at, s.skill.as_deref()), (gh("owner", "repo", None, None), Some("pdf")));
        let s = src("github:owner/repo#v2%2E1@pdf");
        assert_eq!((s.at, s.skill.as_deref()), (gh("owner", "repo", Some("v2.1"), None), Some("pdf")));
        assert_eq!(src("https://github.com/owner/repo/blob/main/skills/pdf/SKILL.md").at, gh("owner", "repo", Some("main"), Some("skills/pdf")));
        assert_eq!(src("https://github.com/o/r.git").at, gh("o", "r", None, None));
        assert_eq!(src("bunx skills add owner/repo -s=x --skill=y").skill.as_deref(), Some("y"));
        assert_eq!(src("npx skills add o/r --skill *").skill, None);
        assert_eq!(
            src("https://gitlab.com/g/sub/r/-/tree/v1/skills").at,
            Source::GitLab { project: "https://gitlab.com/g/sub/r".into(), r#ref: Some("v1".into()), path: Some("skills".into()) }
        );
        assert_eq!(src("gitlab:g/r.git").at, Source::GitLab { project: "https://gitlab.com/g/r".into(), r#ref: None, path: None });
        assert_eq!(
            src("https://git.example.com:8443/g/r/-/tree/main").at,
            Source::GitLab { project: "https://git.example.com:8443/g/r".into(), r#ref: Some("main".into()), path: None }
        );
        assert_eq!(src("https://github.com/o/r/archive/main.zip").at, Source::Download { url: "https://github.com/o/r/archive/main.zip".into() });
        assert_eq!(src("https://raw.githubusercontent.com/o/r/main/SKILL.md").at.id(), "https://raw.githubusercontent.com/o/r/main/SKILL.md");
        assert_eq!(src("https://example.com/x").at, Source::Site { url: "https://example.com/x".into() });
        assert_eq!(src("/Users/me/skills").at, Source::Local { path: "/Users/me/skills".into() });
        assert_eq!(src("~/skills").at, Source::Local { path: "~/skills".into() });
        assert_eq!(src(r"C:\skills").at, Source::Local { path: r"C:\skills".into() });
        for bad in ["", "npx skills add", "just-a-word", "o/r/../../etc", "https://github.com/o"] {
            assert!(SkillSource::parse(bad).is_err(), "{bad}");
        }
        assert_eq!(
            src("o/r/skills#dev@pdf").to_json(),
            json!({ "source": { "type": "github", "owner": "o", "repo": "r", "ref": "dev", "path": "skills" }, "skill": "pdf" })
        );

        let g = GitHubSource::parse("owner/repo@pdf").unwrap();
        assert_eq!((g.id(), g.skill.as_deref()), ("owner/repo".to_string(), Some("pdf")));
        assert_eq!(GitHubSource::parse("o/r").unwrap().archive_url(), "https://codeload.github.com/o/r/tar.gz/HEAD");
        assert!(GitHubSource::parse("https://gitlab.com/a/b").is_err());
    }

    #[test]
    fn skills_are_found_where_the_cli_finds_them() {
        let md = |name: &str| format!("---\nname: {name}\ndescription: Does {name}.\n---\n").into_bytes();
        let files: BTreeMap<String, Vec<u8>> = [
            ("README.md", b"x".to_vec()),
            ("skills/pdf/skill.md", md("PDF Tools")),
            ("skills/pdf/scripts/a.py", b"print()".to_vec()),
            ("skills/pdf/__pycache__/a.pyc", b"x".to_vec()),
            ("skills/pdf/metadata.json", b"{}".to_vec()),
            ("skills/pdf/inner/SKILL.md", md("Inner")),
            (".claude/skills/web/SKILL.md", md("Web")),
            ("node_modules/x/SKILL.md", md("No")),
        ]
        .into_iter()
        .map(|(k, v)| (k.to_string(), v))
        .collect();
        let found = find(&files, None);
        let names: Vec<&str> = found.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(names, ["PDF Tools", "Web"], "the nearest SKILL.md takes in the ones below it");
        assert_eq!(found[0].files.keys().collect::<Vec<_>>(), ["SKILL.md", "inner/SKILL.md", "scripts/a.py"]);
        assert_eq!(find(&files, Some("skills/pdf/inner"))[0].name, "Inner");
        let by_path = find_paths(files.keys().map(String::as_str), |p| files.get(p).map(|b| String::from_utf8_lossy(b).into_owned()), None);
        assert_eq!(by_path[0].files[0], ("SKILL.md".to_string(), "skills/pdf/skill.md".to_string()));
        assert!(is_skill_md("a/Skill.MD") && !is_skill_md("a/skill.md.bak"));
        assert_eq!(dir_name("PDF Tools!"), "pdf-tools");
        assert_eq!(dir_name("..."), "unnamed-skill");
    }

    #[test]
    fn the_tool_reads_what_is_in_a_skill_only() {
        let root = std::env::temp_dir().join(format!("fl-pi-llm-skills-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let dir = root.join("cleanup");
        std::fs::create_dir_all(dir.join("scripts")).unwrap();
        std::fs::write(dir.join("SKILL.md"), "---\nname: Cleanup\ndescription: Frees space.\n---\nSee scripts/run.sh\n").unwrap();
        std::fs::write(dir.join("scripts/run.sh"), "docker system prune\n").unwrap();
        std::fs::create_dir_all(root.join("broken")).unwrap();
        std::fs::write(root.join("secret.txt"), "no").unwrap();
        #[cfg(unix)]
        std::os::unix::fs::symlink(root.join("secret.txt"), dir.join("link.txt")).unwrap();

        let skills = Skills::new(&root);
        let list = skills.list();
        assert_eq!(list, vec![Skill { dir: "cleanup".into(), name: "Cleanup".into(), description: "Frees space.".into() }]);
        assert!(prompt(&list).unwrap().ends_with("Available skills:\n- cleanup: Frees space."));
        assert_eq!(prompt(&[]), None);
        assert_eq!(skills.read("cleanup", "../secret.txt"), None);
        assert_eq!(skills.read("..", "secret.txt"), None);
        assert_eq!(skills.read("cleanup", "link.txt"), None, "a link out of the skill");

        let res = skills.run_tool(&list, &json!({ "name": "Cleanup" })).unwrap();
        assert!(res.ends_with("(read one with `file`):\n- scripts/run.sh"), "{res}");
        assert_eq!(skills.run_tool(&list, &json!({ "name": "cleanup", "file": "scripts/run.sh" })).unwrap(), "docker system prune\n");
        assert!(skills.run_tool(&list, &json!({ "name": "broken" })).is_err());
        assert!(skills.run_tool(&list, &json!({ "name": "cleanup", "file": "../../secret.txt" })).is_err());
        std::fs::remove_dir_all(&root).unwrap();
    }
}
