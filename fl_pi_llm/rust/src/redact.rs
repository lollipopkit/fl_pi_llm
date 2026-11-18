//! Outbound redaction: secrets in what is sent to a model, replaced by
//! placeholders that are put back in the answer.
//!
//! A conversation carries whatever the machine it is about printed — a
//! command's output, a config file, an environment dump — and some of that is
//! a live credential. The model endpoint is somebody else's, so the rule is
//! the one a log would follow: a secret does not leave the device.
//!
//! **Only what a pattern can recognise.** A rule that guessed at host names or
//! bare words would rewrite the conversation into something the model cannot
//! answer about, and a false positive costs a wrong answer while a false
//! negative costs a credential. So the rules below match shapes that are their
//! own evidence: a private-key block, a token with a vendor's fixed prefix, a
//! JWT's three-part header, a URL that carries a password, a bearer token, a
//! `key=value` whose key names a credential.
//!
//! **Placeholders are reversible within their session.** Each distinct secret
//! keeps one placeholder for as long as the conversation does, so the model
//! can refer to it, and the answer has the real value put back before anyone
//! reads it.
//!
//! Compiled with `regex`'s automata and nothing else: a custom rule is a
//! pattern a person typed, and the one engine here answers in time linear in
//! its input whatever that pattern is.

use std::collections::HashMap;

use regex::Regex;
use serde::{Deserialize, Serialize};

/// A rule a person wrote, on top of the built-in ones.
///
/// `pattern` is a Rust `regex` — the same syntax the built-ins use. With no
/// `group` the whole match is what is replaced; with one, only that capture,
/// which is how a rule keeps the part of a line worth reading.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Rule {
    pub pattern: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub group: Option<usize>,
    /// What the rule is, in a log or a settings page.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub enabled: Option<bool>,
}

/// What to keep out of the conversation, and how it is put back.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// Off is the built-in rules too: a caller that turns this off sends
    /// everything, and gets no placeholders to restore.
    pub enabled: bool,
    /// Never touched, whatever else matches: a host name that keeps coming up
    /// is often the point of the conversation.
    pub allow: Vec<String>,
    /// Prefixes a host issues for a value it keeps itself — `sec_` and the
    /// like. Such a string is a handle the model is meant to hold, so it is
    /// never treated as a secret; hiding it would leave the host unable to
    /// trade it back.
    pub handles: Vec<String>,
    /// Built-in kinds switched off by name — the same names a placeholder
    /// carries, `github_token` and the like. Empty keeps every one.
    pub off: Vec<String>,
    pub custom: Vec<Rule>,
}

impl Settings {
    /// Every rule on, nothing allowed or treated as a handle, nothing added.
    pub fn conservative() -> Self {
        Self { enabled: true, allow: Vec::new(), handles: Vec::new(), off: Vec::new(), custom: Vec::new() }
    }
}

/// A built-in rule, as a settings page lists it: the kind its placeholders
/// are named after, and what it matches.
#[derive(Debug, Clone, Serialize)]
pub struct BuiltinRule {
    pub kind: &'static str,
    pub pattern: &'static str,
}

/// Every built-in rule, in the order they apply.
pub fn builtin_rules() -> Vec<BuiltinRule> {
    BUILTIN.iter().map(|&(kind, pattern, _)| BuiltinRule { kind, pattern }).collect()
}

/// Why [settings] would be refused, naming every rule that does not compile.
pub fn check(settings: &Settings) -> Result<(), String> {
    let (_, errors) = compile(settings);
    if errors.is_empty() { Ok(()) } else { Err(errors.join("; ")) }
}

/// Every rule [settings] keeps on, and why each one left out does not compile.
fn compile(settings: &Settings) -> (Vec<(Compiled, String)>, Vec<String>) {
    let mut rules = Vec::new();
    let mut errors = Vec::new();
    for &(kind, pattern, group) in BUILTIN {
        if settings.off.iter().any(|o| o == kind) {
            continue;
        }
        match Compiled::new(pattern, group) {
            Ok(c) => rules.push((c, kind.to_string())),
            Err(e) => errors.push(format!("built-in {kind}: {e}")),
        }
    }
    for rule in settings.custom.iter().filter(|r| r.enabled.unwrap_or(true)) {
        let name = rule.name.clone().unwrap_or_else(|| "custom".into());
        match Compiled::new(&rule.pattern, rule.group) {
            Ok(c) => rules.push((c, name)),
            Err(e) => errors.push(format!("{}: {e}", rule.name.as_deref().unwrap_or(&rule.pattern))),
        }
    }
    (rules, errors)
}

/// What one rule matched, before it becomes a placeholder.
struct Hit {
    start: usize,
    end: usize,
    /// Which rule: the placeholder says what kind of secret was hidden, which
    /// is what a reader of the conversation or its log needs.
    kind: String,
}

/// One conversation's redaction: the rules compiled once, and the secrets it
/// has already hidden.
pub struct Redactor {
    rules: Vec<(Compiled, String)>,
    allow: Vec<String>,
    /// A value starting with one of these is a handle, not a secret.
    handles: Vec<String>,
    /// Off keeps everything else: what was hidden before is still put back,
    /// because a placeholder already handed out is the app's own secret.
    enabled: bool,
    /// Real value → placeholder, and back. Keyed by the value so the same
    /// secret keeps the same name across turns.
    hidden: HashMap<String, String>,
    restore: HashMap<String, String>,
    /// [restore]'s placeholders, longest first, so `_10_` is not eaten by
    /// `_1_`. Rebuilt when one is handed out, which is rare.
    ordered: Vec<String>,
    /// How many of each kind have been handed out.
    counts: HashMap<String, usize>,
    /// What was hidden since the last [take_report], by kind.
    hits: HashMap<String, usize>,
}

struct Compiled {
    re: Regex,
    group: Option<usize>,
}

impl Compiled {
    fn new(pattern: &str, group: Option<usize>) -> Result<Self, String> {
        let re = Regex::new(pattern).map_err(|e| e.to_string())?;
        // `captures_len` counts the whole match as group 0.
        if let Some(g) = group
            && g >= re.captures_len()
        {
            return Err(format!("no group {g} in the pattern"));
        }
        Ok(Self { re, group })
    }

    /// The span this rule wants replaced: the whole match, or one capture of
    /// it where the rule names a group.
    fn span(&self, c: &regex::Captures<'_>) -> Option<(usize, usize)> {
        let m = match self.group {
            None => c.get(0)?,
            Some(i) => c.get(i)?,
        };
        Some((m.start(), m.end()))
    }

    fn hits(&self, text: &str, kind: &str) -> Vec<Hit> {
        self.re
            .captures_iter(text)
            .filter_map(|c| {
                let (start, end) = self.span(&c)?;
                (start < end).then(|| Hit { start, end, kind: kind.to_string() })
            })
            .collect()
    }
}

/// The shortest placeholder this module makes — `__SBM_` and its `__`. A tail
/// shorter than this is never held for one.
const MIN_PLACEHOLDER: usize = 4;

const PLACEHOLDER_START: &str = "__SBM_";

/// Sixteen hex characters, from the system's randomness.
///
/// Unguessable rather than merely unique: a model that writes a placeholder it
/// was not given must not be able to name one this redactor issued.
fn nonce() -> String {
    let mut buf = [0u8; 8];
    if getrandom::fill(&mut buf).is_err() {
        // A broken system; still unique within the process.
        buf = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos() as u64)
            .unwrap_or(0)
            .to_le_bytes();
    }
    buf.iter().map(|b| format!("{b:02x}")).collect()
}

/// Whether [tail] could be the beginning of a placeholder nobody has been
/// given yet, which is what a redactor with no hidden values still has to
/// hold back.
fn looks_like_prefix(tail: &str) -> bool {
    PLACEHOLDER_START.starts_with(tail) || tail.starts_with(PLACEHOLDER_START)
}

/// The built-in rules, `(kind, pattern, group)`: what is its own evidence.
///
/// Deliberately short. Each entry is a shape that cannot be an ordinary word
/// in an ordinary sentence. Adding a loose one here is how the feature starts
/// rewriting conversations it should leave alone.
const BUILTIN: &[(&str, &str, Option<usize>)] = &[
    // A private key, whole: the base64 body would match nothing else.
    (
        "private_key",
        r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----",
        None,
    ),
    // Vendor tokens: the prefix is the evidence, the length floor keeps a word
    // that merely starts with `sk-` out. `sk-ant-…` is covered by the `-`.
    ("api_key", r"\bsk-[A-Za-z0-9_\-]{16,}", None),
    ("github_token", r"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}", None),
    ("github_token", r"\bgithub_pat_[A-Za-z0-9_]{20,}", None),
    ("slack_token", r"\bxox[baprs]-[A-Za-z0-9\-]{10,}", None),
    ("aws_key", r"\bAKIA[0-9A-Z]{16}\b", None),
    ("gitlab_token", r"\bglpat-[A-Za-z0-9_\-]{20,}", None),
    ("google_key", r"\bAIza[0-9A-Za-z_\-]{35}", None),
    // Three base64url parts, the header always `{"`.
    ("jwt", r"\beyJ[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}\.[A-Za-z0-9_\-]{8,}", None),
    // Only the password: scheme, user and host are what the conversation is
    // about.
    ("url_password", r"://[^/\s:@]+:([^/\s@]+)@", Some(1)),
    // `Authorization: Bearer …`, the token only.
    ("bearer_token", r"(?i)\bbearer\s+([A-Za-z0-9._~+/\-]{16,}=*)", Some(1)),
    // `key=value` / `key: value` where the key names a credential; only the
    // value is replaced. The leading class anchors the key without a
    // lookbehind, so `DB_PASSWORD=` reads as the key it is. `pwd` is not a
    // key here: `PWD=/home/…` is in every environment dump.
    (
        "secret",
        r#"(?i)(?:^|[^A-Za-z0-9])(?:password|passwd|secret|token|api[_\-]?key|access[_\-]?key|private[_\-]?key|client[_\-]?secret|auth[_\-]?token|bearer)\b["']?\s*[:=]\s*["']?([^\s'",;]{6,})"#,
        Some(1),
    ),
];

impl Redactor {
    /// `Err` naming every rule that does not compile.
    pub fn new(settings: &Settings) -> Result<Self, String> {
        let mut r = Self::empty();
        r.apply(settings)?;
        Ok(r)
    }

    /// [settings] without the rules that do not compile, and why each one
    /// was left out: what a stored setting starts with, where refusing to
    /// start would leave no Agent over a typo.
    pub fn lenient(settings: &Settings) -> (Self, Vec<String>) {
        let mut r = Self::empty();
        let errors = r.apply_lenient(settings);
        (r, errors)
    }

    /// [Redactor::apply] without the rules that do not compile, answering why
    /// each was left out: a bad rule costs itself, never the rest.
    pub fn apply_lenient(&mut self, settings: &Settings) -> Vec<String> {
        let (rules, errors) = compile(settings);
        self.install(rules, settings);
        errors
    }

    fn empty() -> Self {
        Self {
            rules: Vec::new(),
            allow: Vec::new(),
            handles: Vec::new(),
            enabled: false,
            hidden: HashMap::new(),
            restore: HashMap::new(),
            ordered: Vec::new(),
            counts: HashMap::new(),
            hits: HashMap::new(),
        }
    }

    /// Replaces the rules, keeping what was already hidden restorable: a
    /// placeholder handed out earlier must not be stranded in the
    /// conversation. A rule that does not compile leaves the ones in force.
    pub fn apply(&mut self, settings: &Settings) -> Result<(), String> {
        let (rules, errors) = compile(settings);
        if !errors.is_empty() {
            return Err(errors.join("; "));
        }
        self.install(rules, settings);
        Ok(())
    }

    fn install(&mut self, rules: Vec<(Compiled, String)>, settings: &Settings) {
        self.rules = rules;
        self.allow = settings.allow.iter().filter(|a| !a.is_empty()).cloned().collect();
        self.handles = settings.handles.iter().filter(|h| !h.is_empty()).cloned().collect();
        self.enabled = settings.enabled;
    }

    /// Turns the rules off or on for what is sent from now on.
    ///
    /// What was already hidden stays restorable: a conversation the model was
    /// sent with placeholders in it still answers with them.
    pub fn set_enabled(&mut self, enabled: bool) {
        self.enabled = enabled;
    }

    /// [text] with every secret replaced, and the placeholders this turn added.
    ///
    /// Longest match wins where two rules overlap, so a private key is one
    /// placeholder rather than a block plus a field inside it.
    pub fn redact(&mut self, text: &str) -> String {
        if !self.enabled || text.is_empty() || self.rules.is_empty() {
            return text.to_string();
        }
        let mut hits = Vec::new();
        for (rule, kind) in &self.rules {
            hits.extend(rule.hits(text, kind));
        }
        if hits.is_empty() {
            return text.to_string();
        }
        // Leftmost, and the longest at a given start; an overlap inside one
        // already taken is dropped.
        hits.sort_by(|a, b| a.start.cmp(&b.start).then(b.end.cmp(&a.end)));
        let mut taken: Vec<Hit> = Vec::new();
        let mut end = 0;
        for hit in hits {
            if hit.start < end {
                continue;
            }
            end = hit.end;
            taken.push(hit);
        }

        let mut out = String::with_capacity(text.len());
        let mut at = 0;
        for hit in taken {
            let value = &text[hit.start..hit.end];
            if self.allow.iter().any(|a| value.contains(a.as_str())) {
                continue;
            }
            // A host's own handle: the model is meant to hold this, and the
            // host trades it back for the value it stands for.
            if self.handles.iter().any(|h| value.trim().starts_with(h.as_str())) {
                continue;
            }
            out.push_str(&text[at..hit.start]);
            out.push_str(&self.placeholder(value, &hit.kind));
            at = hit.end;
        }
        out.push_str(&text[at..]);
        out
    }

    fn placeholder(&mut self, value: &str, kind: &str) -> String {
        if let Some(existing) = self.hidden.get(value) {
            return existing.clone();
        }
        let n = {
            let c = self.counts.entry(kind.to_string()).or_insert(0);
            *c += 1;
            *c
        };
        // Letters, digits and `_` only, so it survives being quoted back.
        let label: String = kind
            .chars()
            .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_uppercase() } else { '_' })
            .collect();
        // The nonce keeps a placeholder from being a way in: one a model or
        // a fetched page guesses restores nothing.
        let nonce = nonce();
        let placeholder = format!("__SBM_{label}_{n}_{nonce}__");
        self.hidden.insert(value.to_string(), placeholder.clone());
        self.restore.insert(placeholder.clone(), value.to_string());
        // Kept longest first, so `_10_` is not eaten by `_1_`.
        let at = self.ordered.partition_point(|p| p.len() >= placeholder.len());
        self.ordered.insert(at, placeholder.clone());
        *self.hits.entry(kind.to_string()).or_insert(0) += 1;
        placeholder
    }

    /// [text] with each placeholder replaced by what it hid. A placeholder
    /// split across two chunks never matches, which is what makes streaming
    /// safe: a caller restores what it can and keeps the rest for the next.
    pub fn restore_in(&self, text: &str) -> String {
        if self.restore.is_empty() {
            return text.to_string();
        }
        let mut out = text.to_string();
        // Longest first, so `_10_` is not eaten by `_1_`.
        for placeholder in &self.ordered {
            if out.contains(placeholder.as_str()) {
                let value = &self.restore[placeholder];
                out = out.replace(placeholder.as_str(), value);
            }
        }
        out
    }

    /// [json] with each placeholder put back *as a JSON value*: a secret with
    /// a quote or a newline in it is escaped, so the document still parses.
    ///
    /// What a `Result` carries is JSON, and a PEM key pasted into it
    /// unescaped would break every reader downstream.
    pub fn restore_json(&self, json: &str) -> String {
        if self.restore.is_empty() {
            return json.to_string();
        }
        let mut out = json.to_string();
        for placeholder in &self.ordered {
            if out.contains(placeholder.as_str()) {
                let value = &self.restore[placeholder];
                out = out.replace(placeholder.as_str(), &escape_json(value));
            }
        }
        out
    }

    /// [text], a value about to be stored, with each placeholder put back: as
    /// a JSON value when [text] is a JSON document, as it is otherwise.
    pub fn restore_stored(&self, text: &str) -> String {
        if self.restore.is_empty() || !text.contains(PLACEHOLDER_START) {
            return text.to_string();
        }
        match serde_json::from_str::<serde::de::IgnoredAny>(text) {
            Ok(_) => self.restore_json(text),
            Err(_) => self.restore_in(text),
        }
    }

    /// How many of each kind were hidden since the last call, or None when
    /// nothing was: a caller reports a turn that hid something, once.
    pub fn take_report(&mut self) -> Option<HashMap<String, usize>> {
        (!self.hits.is_empty()).then(|| std::mem::take(&mut self.hits))
    }

    /// How many bytes at the end of [text] could still turn into one of this
    /// redactor's placeholders.
    ///
    /// A placeholder is `__SBM_…__`, so a tail holding no `_` cannot be one,
    /// and the answer is usually zero. Nothing longer than the longest
    /// placeholder this redactor has handed out is ever a prefix of one.
    pub fn partial_placeholder_len(&self, text: &str) -> usize {
        if !text.ends_with(|c: char| c == '_' || c.is_ascii_alphanumeric()) {
            return 0;
        }
        let longest = self
            .restore
            .keys()
            .map(|p| p.len())
            .max()
            .unwrap_or(0)
            .max(MIN_PLACEHOLDER);
        let bytes = text.as_bytes();
        let cap = longest.min(bytes.len());
        // Right to left from the longest tail that could fit, so the longest
        // real prefix wins.
        for len in (1..=cap).rev() {
            // A cut inside a character is not a prefix of anything, and
            // slicing there would panic. Placeholders are ASCII.
            let at = bytes.len() - len;
            if !text.is_char_boundary(at) {
                continue;
            }
            let tail = &text[at..];
            if self.restore.keys().any(|p| p.starts_with(tail)) || looks_like_prefix(tail) {
                return len;
            }
        }
        0
    }
}

/// [value] as the inside of a JSON string.
///
/// Written here rather than through `serde_json` so that a placeholder inside
/// a longer string is put back without the surrounding document being walked
/// and re-serialised on every chunk.
fn escape_json(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for c in value.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out
}

/// Puts placeholders back in a stream, where one may straddle two chunks.
///
/// A chunk boundary falls anywhere: inside a placeholder, and — because a body
/// arrives as bytes — inside a multi-byte character. Both are held back until
/// the next chunk says what they were, so nothing is shown half-restored and
/// no byte is dropped.
///
/// Only the longest tail that could still become a placeholder is held, so a
/// stream with no placeholders in it comes straight through.
#[derive(Default)]
pub struct StreamRestorer {
    /// Bytes not yet decoded into text: an incomplete character.
    undecoded: Vec<u8>,
    /// Decoded text held back because it could still be the start of a
    /// placeholder.
    held: String,
    /// Whether the stream is a JSON document, where a value with a quote or a
    /// newline in it has to be escaped to keep the document readable. Off for
    /// text that is handed over as it is, such as a streamed answer's delta,
    /// whose own JSON wrapper escapes it afterwards.
    json: bool,
}

impl StreamRestorer {
    /// For a stream that is text: a streamed answer.
    pub fn new() -> Self {
        Self::default()
    }

    /// For a stream that is a JSON document: a response body.
    pub fn new_json() -> Self {
        Self { json: true, ..Self::default() }
    }

    /// [chunk] with every complete placeholder restored; an unfinished one
    /// waits for the next chunk.
    pub fn push(&mut self, chunk: &[u8], redactor: &Redactor) -> Vec<u8> {
        self.undecoded.extend_from_slice(chunk);
        let mut text = std::mem::take(&mut self.held);
        let valid = match std::str::from_utf8(&self.undecoded) {
            Ok(t) => {
                text.push_str(t);
                self.undecoded.clear();
                return self.emit(text, redactor);
            }
            Err(e) => e.valid_up_to(),
        };
        let (valid, rest) = self.undecoded.split_at(valid);
        text.push_str(&String::from_utf8_lossy(valid));
        self.undecoded = rest.to_vec();
        self.emit(text, redactor)
    }

    /// Whatever was held, at the end of the body.
    pub fn finish(&mut self, redactor: &Redactor) -> Vec<u8> {
        let mut text = std::mem::take(&mut self.held);
        if !self.undecoded.is_empty() {
            text.push_str(&String::from_utf8_lossy(&self.undecoded));
            self.undecoded.clear();
        }
        self.restore(&text, redactor).into_bytes()
    }

    /// Restores what is complete and keeps the tail that could still be a
    /// placeholder.
    fn emit(&mut self, text: String, redactor: &Redactor) -> Vec<u8> {
        let keep = redactor.partial_placeholder_len(&text);
        let split = text.len() - keep;
        let out = self.restore(&text[..split], redactor);
        self.held = text[split..].to_string();
        out.into_bytes()
    }

    fn restore(&self, text: &str, redactor: &Redactor) -> String {
        match self.json {
            true => redactor.restore_json(text),
            false => redactor.restore_in(text),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// What a placeholder for [kind] and [n] looks like, with the nonce left
    /// out: a test asserts the shape, never the random part.
    fn shape(kind: &str, n: usize) -> String {
        format!("__SBM_{kind}_{n}_")
    }

    /// Whether [text] holds exactly one placeholder whose kind and number are
    /// [kind] and [n].
    fn is_placeholder(text: &str, kind: &str, n: usize) -> bool {
        let Some(start) = text.find(PLACEHOLDER_START) else { return false };
        let inside = &text[start + PLACEHOLDER_START.len()..];
        let head = &shape(kind, n)[PLACEHOLDER_START.len()..];
        if !inside.starts_with(head) {
            return false;
        }
        let nonce = &inside[head.len()..];
        nonce.len() > 16
            && nonce.ends_with("__")
            && nonce[..nonce.len() - 2].chars().all(|c| c.is_ascii_hexdigit())
    }

    fn redactor() -> Redactor {
        Redactor::new(&Settings::conservative()).unwrap()
    }

    #[test]
    fn a_private_key_is_one_placeholder() {
        let mut r = redactor();
        let key = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3BlbnNzaC1rZXk\n-----END OPENSSH PRIVATE KEY-----";
        let out = r.redact(&format!("my key:\n{key}\nthanks"));
        assert!(out.starts_with("my key:\n__SBM_PRIVATE_KEY_1_"), "{out}");
        assert!(out.ends_with("__\nthanks"), "{out}");
        assert_eq!(r.restore_in(&out), format!("my key:\n{key}\nthanks"));
    }

    #[test]
    fn vendor_tokens_are_recognised() {
        let mut r = redactor();
        let out = r.redact("use ghp_abcdefghijklmnopqrstuvwxyz012345 and sk-proj-abcdefghijklmnopqrst");
        assert!(out.starts_with("use __SBM_GITHUB_TOKEN_1_"), "{out}");
        assert!(out.contains(" and __SBM_API_KEY_1_"), "{out}");
        assert!(!out.contains("ghp_") && !out.contains("sk-proj-"), "{out}");
    }

    #[test]
    fn an_ordinary_word_that_starts_like_a_token_is_left_alone() {
        let mut r = redactor();
        assert_eq!(r.redact("sk-learn is a Python library"), "sk-learn is a Python library");
    }

    #[test]
    fn a_url_keeps_everything_but_the_password() {
        let mut r = redactor();
        let out = r.redact("postgres://app:hunter2@db:5432/main");
        assert!(out.starts_with("postgres://app:__SBM_URL_PASSWORD_1_"), "{out}");
        assert!(out.ends_with("@db:5432/main"), "{out}");
        assert!(!out.contains("hunter2"), "{out}");
    }

    #[test]
    fn a_named_field_is_hidden_by_its_value() {
        let mut r = redactor();
        let a = r.redact("DB_PASSWORD=hunter2pass");
        assert!(a.starts_with("DB_PASSWORD=__SBM_SECRET_1_"), "{a}");
        assert!(!a.contains("hunter2pass"), "{a}");
        let b = r.redact("token: abcdef123456");
        assert!(b.starts_with("token: __SBM_SECRET_2_"), "{b}");
        assert!(!b.contains("abcdef123456"), "{b}");
    }

    // `PWD=` is in every environment dump, and a path is no secret.
    #[test]
    fn the_working_directory_is_left_alone() {
        let mut r = redactor();
        assert_eq!(r.redact("PWD=/home/lk/proj\npwd: /srv/app"), "PWD=/home/lk/proj\npwd: /srv/app");
    }

    #[test]
    fn a_bearer_token_is_hidden_and_the_header_kept() {
        let mut r = redactor();
        let out = r.redact("curl -H 'Authorization: Bearer abcdef0123456789abcdef'");
        assert!(out.starts_with("curl -H 'Authorization: Bearer __SBM_BEARER_TOKEN_1_"), "{out}");
        assert!(!out.contains("abcdef0123456789abcdef"), "{out}");
    }

    #[test]
    fn a_group_the_pattern_lacks_is_refused() {
        let settings = Settings {
            custom: vec![Rule { pattern: "ZZZ([0-9]+)".into(), group: Some(2), name: Some("mine".into()), enabled: None }],
            ..Settings::conservative()
        };
        let err = check(&settings).unwrap_err();
        assert!(err.contains("mine") && err.contains("group 2"), "{err}");
    }

    // What a stored setting starts with: the bad rule is left out, and
    // everything else it says still holds.
    #[test]
    fn lenient_drops_only_the_rule_that_does_not_compile() {
        let (mut r, errors) = Redactor::lenient(&Settings {
            handles: vec!["sec_".into()],
            off: vec!["aws_key".into()],
            custom: vec![
                Rule { pattern: "(unclosed".into(), group: None, name: Some("bad".into()), enabled: None },
                Rule { pattern: r"\bZZZ[0-9]{4}\b".into(), group: None, name: Some("mine".into()), enabled: None },
            ],
            ..Settings::conservative()
        });
        assert_eq!(errors.len(), 1, "{errors:?}");
        assert!(errors[0].contains("bad"));
        assert_eq!(r.redact("AKIAABCDEFGHIJKLMNOP"), "AKIAABCDEFGHIJKLMNOP");
        assert!(r.redact("ZZZ1234").starts_with("__SBM_MINE_1_"));
        assert_eq!(r.redact("token: sec_abcdefghijkl"), "token: sec_abcdefghijkl");
    }

    #[test]
    fn the_same_secret_keeps_one_placeholder() {
        let mut r = redactor();
        let a = r.redact("AKIAABCDEFGHIJKLMNOP");
        let b = r.redact("again AKIAABCDEFGHIJKLMNOP");
        assert!(is_placeholder(&a, "AWS_KEY", 1), "{a}");
        assert_eq!(b, format!("again {a}"));
        assert_eq!(r.take_report().unwrap().get("aws_key"), Some(&1));
    }

    #[test]
    fn turning_it_off_stops_hiding_but_keeps_what_was_hidden() {
        let mut r = redactor();
        let out = r.redact("AKIAABCDEFGHIJKLMNOP");
        r.set_enabled(false);
        assert_eq!(r.redact("AKIAABCDEFGHIJKLMNOP"), "AKIAABCDEFGHIJKLMNOP");
        // The placeholder the model was already sent still comes back.
        assert_eq!(r.restore_in(&out), "AKIAABCDEFGHIJKLMNOP");
    }

    #[test]
    fn a_new_rule_set_keeps_what_was_hidden() {
        let mut r = Redactor::new(&Settings { enabled: true, allow: vec![], handles: vec![], off: vec![], custom: vec![] }).unwrap();
        let hidden = r.redact("AKIAABCDEFGHIJKLMNOP");
        r.apply(&Settings {
            enabled: true,
            allow: Vec::new(),
            handles: vec!["sec_".into()],
            off: Vec::new(),
            custom: vec![Rule {
                pattern: r"\bZZZ[0-9]{4}\b".into(),
                group: None,
                name: Some("mine".into()),
                enabled: None,
            }],
        })
        .unwrap();
        let out = r.redact("code ZZZ1234");
        assert!(out.starts_with("code __SBM_MINE_1_"), "{out}");
        assert_eq!(r.restore_in(&hidden), "AKIAABCDEFGHIJKLMNOP");
    }

    #[test]
    fn a_rule_that_does_not_compile_leaves_the_old_ones_in_force() {
        let mut r = redactor();
        let before = r.redact("AKIAABCDEFGHIJKLMNOP");
        let failed = r.apply(&Settings {
            enabled: true,
            allow: Vec::new(),
            handles: Vec::new(),
            off: Vec::new(),
            custom: vec![Rule { pattern: "(unclosed".into(), group: None, name: None, enabled: None }],
        });
        assert!(failed.is_err());
        assert_eq!(r.redact("AKIAABCDEFGHIJKLMNOP"), before);
    }

    // The one property that keeps a placeholder from being a way in: only
    // what this redactor issued comes back. A model that writes
    // `__SBM_GITHUB_TOKEN_1__` gets its own text back, not somebody's token.
    #[test]
    fn a_guessed_placeholder_restores_nothing() {
        let mut r = redactor();
        let token = "ghp_abcdefghijklmnopqrstuvwxyz012345";
        r.redact(token);
        for guess in [
            "__SBM_GITHUB_TOKEN_1__",
            "__SBM_GITHUB_TOKEN_1_0000000000000000__",
            "__SBM_GITHUB_TOKEN_2__",
            "__SBM_SECRET_1__",
        ] {
            assert_eq!(r.restore_in(guess), guess, "{guess} was taken for one of ours");
        }
    }

    // What a `Result` carries is JSON: a PEM key put back unescaped breaks
    // every reader downstream.
    // A stored chat outlives the nonces: it keeps the values, escaped where
    // it is JSON.
    #[test]
    fn a_stored_value_is_restored_as_what_it_is() {
        let mut r = redactor();
        let key = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3Blbn\n-----END OPENSSH PRIVATE KEY-----";
        let p = r.redact(key);
        let doc = format!(r#"{{"text":"{p}"}}"#);
        let parsed: serde_json::Value = serde_json::from_str(&r.restore_stored(&doc)).unwrap();
        assert_eq!(parsed["text"], key);
        assert_eq!(r.restore_stored(&format!("plain {p}")), format!("plain {key}"));
    }

    #[test]
    fn a_secret_is_put_back_escaped_for_json() {
        let mut r = redactor();
        let key = "-----BEGIN OPENSSH PRIVATE KEY-----\nb3Blbn\n-----END OPENSSH PRIVATE KEY-----";
        let placeholder = r.redact(key);
        let doc = format!(r#"{{"text":"{placeholder}"}}"#);
        let restored = r.restore_json(&doc);
        let parsed: serde_json::Value = serde_json::from_str(&restored).unwrap();
        assert_eq!(parsed["text"], key);
    }

    #[test]
    fn a_report_comes_once_and_names_no_value() {
        let mut r = redactor();
        assert!(r.take_report().is_none());
        r.redact("AKIAABCDEFGHIJKLMNOP and ghp_abcdefghijklmnopqrstuvwxyz012345");
        let report = r.take_report().unwrap();
        assert_eq!(report.get("aws_key"), Some(&1));
        assert_eq!(report.get("github_token"), Some(&1));
        // Taken: the same turn is not reported twice.
        assert!(r.take_report().is_none());
    }

    // The app hands the model a handle it keeps the value behind, so hiding
    // the handle would leave the app unable to trade it back.
    #[test]
    fn a_hosts_handle_is_not_a_secret() {
        let mut r = Redactor::new(&Settings {
            enabled: true,
            allow: Vec::new(),
            handles: vec!["sec_".into()],
            off: Vec::new(),
            custom: Vec::new(),
        })
        .unwrap();
        assert_eq!(
            r.redact(r#"{"pw":{"secret":"sec_abcdefghijkl"}}"#),
            r#"{"pw":{"secret":"sec_abcdefghijkl"}}"#
        );
        // Everything else is still hidden.
        let out = r.redact("token: hunter2hunter2");
        assert!(out.starts_with("token: __SBM_SECRET_1_"), "{out}");
        assert!(!out.contains("hunter2"), "{out}");
    }

    #[test]
    fn allowed_values_are_left_alone() {
        let mut r = Redactor::new(&Settings {
            enabled: true,
            allow: vec!["hunter2".into()],
            handles: Vec::new(),
            off: Vec::new(),
            custom: Vec::new(),
        })
        .unwrap();
        assert_eq!(r.redact("postgres://app:hunter2@db/main"), "postgres://app:hunter2@db/main");
    }

    #[test]
    fn a_custom_rule_is_reported_when_it_does_not_compile() {
        let err = Redactor::new(&Settings {
            enabled: true,
            allow: Vec::new(),
            handles: Vec::new(),
            off: Vec::new(),
            custom: vec![Rule { pattern: "(unclosed".into(), group: None, name: Some("mine".into()), enabled: None }],
        });
        assert!(err.is_err());
        assert!(err.err().unwrap().contains("mine"));
    }

    #[test]
    fn a_placeholder_split_across_chunks_is_restored() {
        let mut r = redactor();
        let redacted = r.redact("key AKIAABCDEFGHIJKLMNOP done");
        let bytes = redacted.as_bytes();
        // Every split point, including inside the placeholder itself.
        for at in 0..bytes.len() {
            let mut s = StreamRestorer::new();
            let mut out = s.push(&bytes[..at], &r);
            out.extend(s.push(&bytes[at..], &r));
            out.extend(s.finish(&r));
            assert_eq!(
                String::from_utf8(out).unwrap(),
                "key AKIAABCDEFGHIJKLMNOP done",
                "split at {at}"
            );
        }
    }

    #[test]
    fn a_character_split_across_chunks_survives() {
        let r = redactor();
        let text = "温度 25°C";
        let bytes = text.as_bytes();
        for at in 0..bytes.len() {
            let mut s = StreamRestorer::new();
            let mut out = s.push(&bytes[..at], &r);
            out.extend(s.push(&bytes[at..], &r));
            out.extend(s.finish(&r));
            assert_eq!(String::from_utf8(out).unwrap(), text, "split at {at}");
        }
    }

    #[test]
    fn a_stream_with_nothing_hidden_is_passed_straight_through() {
        let r = redactor();
        let mut s = StreamRestorer::new();
        let out = s.push(b"{\"cpu\": 12.5}", &r);
        assert_eq!(String::from_utf8(out).unwrap(), "{\"cpu\": 12.5}");
        assert!(s.finish(&r).is_empty());
    }

    // What `engine.rs` runs on a tool call before the host sees it: the model
    // only ever saw placeholders, so an argument it wrote with one in it is
    // the app's own secret being handed to a tool.
    #[test]
    fn a_tool_call_argument_is_put_back() {
        let mut r = redactor();
        r.redact("AKIAABCDEFGHIJKLMNOP");
        let args = r#"{"tz":"AKIAABCDEFGHIJKLMNOP"}"#;
        let redacted = r.restore_in(args).replace("AKIAABCDEFGHIJKLMNOP", "x");
        assert_eq!(redacted, r#"{"tz":"x"}"#);
        // The placeholder the model would have written is what is put back.
        let placeholder = r.redact("AKIAABCDEFGHIJKLMNOP");
        let from_model = format!(r#"{{"tz":"{placeholder}"}}"#);
        assert_eq!(r.restore_in(&from_model), args);
    }

    #[test]
    fn restoring_takes_the_longest_first() {
        let mut r = redactor();
        // Ten distinct keys, so the tenth placeholder is `_10_`: taken as a
        // prefix, `_1` would be found inside it.
        for c in b'A'..=b'J' {
            r.redact(&format!("AKIA{}", (c as char).to_string().repeat(16)));
        }
        // The placeholders this redactor issued, so the nonce is the real
        // one: `_10_` must not be taken for `_1_`.
        let ten = r.redact("AKIAJJJJJJJJJJJJJJJJ");
        let one = r.redact("AKIAAAAAAAAAAAAAAAAA");
        let text = format!("{ten} and {one}");
        assert_eq!(
            r.restore_in(&text),
            "AKIAJJJJJJJJJJJJJJJJ and AKIAAAAAAAAAAAAAAAAA"
        );
    }
}
