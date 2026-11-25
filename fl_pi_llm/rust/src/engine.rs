//! The JavaScript runtime: one QuickJS context on a thread of its own.
//!
//! QuickJS values are not `Send`, so everything that touches them happens on
//! the engine thread. The outside world talks to it with [`Inbound`] messages
//! and hears back through the `sink` given to [`Engine::spawn`]. Nothing on
//! the engine thread blocks except the wait for the next message, which is
//! bounded by the next timer.

use std::cell::RefCell;
use std::collections::{HashMap, VecDeque};
use std::rc::Rc;
use std::sync::mpsc::{self, Receiver, RecvTimeoutError, Sender};
use std::sync::Arc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use rquickjs::function::Opt;
use rquickjs::{
    Array, Context, Ctx, Exception, Function, Object, Persistent, Promise, Runtime, TypedArray, Value,
};
use rusqlite::types::{Value as SqlValue, ValueRef};

use crate::db::{Chats, Storage};
use crate::redact::{Redactor, Settings, StreamRestorer};

/// The bundle built from `js/`: pi-durable, pi-ai and the Web layer, as
/// QuickJS bytecode compiled by `build.rs`. Empty on 32-bit targets.
static BYTECODE: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/fl_pi_llm.qbc"));

/// The same bundle as source, for the targets that have no bytecode.
#[cfg(not(target_pointer_width = "64"))]
const SOURCE: &str = include_str!("../js/fl_pi_llm.js");

/// QuickJS heap ceiling. A chat is read from its database a page at a time,
/// so what is held is what is shown; a runaway is a bug.
const MEMORY_LIMIT: usize = 512 * 1024 * 1024;
/// The SDKs recurse through deep JSON; QuickJS's default is too small for them.
const STACK_LIMIT: usize = 4 * 1024 * 1024;

/// What the engine can be asked to do.
#[derive(Debug)]
pub enum Inbound {
    /// Call `__fl.dispatch(method, payload)`. Answered with [`Outbound::Result`].
    Request { req_id: u64, method: String, payload: String },
    /// The host's answer to an [`Outbound::HostCall`].
    Answer { call_id: u64, result: Result<String, String> },
    /// A chunk of a response body opened by a `fetch` host call.
    BodyChunk { stream_id: u64, chunk: Vec<u8> },
    /// The end of a response body, with the error that ended it if any.
    BodyEnd { stream_id: u64, error: Option<String> },
    /// What to keep out of what is sent from now on, replacing whatever was
    /// in force. `None` sends everything.
    ///
    /// Applied to a running engine so that a settings switch takes effect
    /// without a restart, and without losing the placeholders already handed
    /// out in the chats that are open.
    Redact { settings: Option<Settings> },
    Shutdown,
}

/// What the engine tells the host.
#[derive(Debug, Clone)]
pub enum Outbound {
    /// The JSON `{ok, value | error}` a [`Inbound::Request`] resolved to.
    Result { req_id: u64, payload: String },
    /// Something only the host can do. Answer with [`Inbound::Answer`].
    HostCall { call_id: u64, name: String, payload: String, body: Option<Vec<u8>> },
    /// Something the host should know, needing no answer.
    Notify { name: String, payload: String },
    /// An event from a session or a completion, as JSON.
    Event { payload: String },
    Log { level: String, message: String },
    /// The engine could not start or stopped on its own. It is gone.
    Fatal { message: String },
}

pub type Sink = Arc<dyn Fn(Outbound) + Send + Sync>;

/// A handle to a running engine. Dropping it shuts the engine down.
pub struct Engine {
    tx: Sender<Inbound>,
    thread: Option<JoinHandle<()>>,
}

impl Engine {
    /// Starts an engine keeping its chats in [storage]; without one, opening
    /// a chat fails.
    /// [redact] is what to keep out of what is sent to a model; `None` sends
    /// everything.
    pub fn spawn(sink: Sink, storage: Option<Storage>, redact: Option<Settings>) -> std::io::Result<Self> {
        let (tx, rx) = mpsc::channel();
        let thread = std::thread::Builder::new()
            .name("fl_pi_llm".into())
            // QuickJS runs on this thread's stack; the limit above has to fit.
            .stack_size(STACK_LIMIT * 2)
            .spawn(move || {
                if let Err(e) = run(rx, sink.clone(), storage, redact) {
                    sink(Outbound::Fatal { message: e });
                }
            })?;
        Ok(Self { tx, thread: Some(thread) })
    }

    /// Queues a message. `false` when the engine has already stopped.
    pub fn send(&self, msg: Inbound) -> bool {
        self.tx.send(msg).is_ok()
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        let _ = self.tx.send(Inbound::Shutdown);
        if let Some(t) = self.thread.take() {
            let _ = t.join();
        }
    }
}

type Pf = Persistent<Function<'static>>;

struct Timer {
    due: Instant,
    every: Option<Duration>,
    cb: Pf,
}

#[derive(Default)]
struct BodyStream {
    queue: VecDeque<Vec<u8>>,
    /// `Some` once the body has ended; the inner value is the error, if any.
    ended: Option<Option<String>>,
    /// A `read` waiting for the next chunk.
    waiter: Option<(Pf, Pf)>,
}

struct State {
    sink: Sink,
    next_call: u64,
    calls: HashMap<u64, (Pf, Pf)>,
    streams: HashMap<u64, BodyStream>,
    next_timer: u32,
    timers: HashMap<u32, Timer>,
    chats: Chats,
    /// One for the whole engine: a `fetch` carries no session of its own.
    redactor: Option<Redactor>,
    /// One per response body, so a placeholder split across chunks is put
    /// back whole.
    restorers: HashMap<u64, StreamRestorer>,
    /// One per content block of a streamed answer, by session and
    /// `contentIndex`: a model writes a placeholder token by token, so it is
    /// whole only across deltas, never inside one body chunk.
    answer_restorers: HashMap<(String, u64), StreamRestorer>,
}

type Shared = Rc<RefCell<State>>;

fn run(rx: Receiver<Inbound>, sink: Sink, storage: Option<Storage>, redact: Option<Settings>) -> Result<(), String> {
    let rt = Runtime::new().map_err(|e| format!("QuickJS runtime: {e}"))?;
    rt.set_memory_limit(MEMORY_LIMIT);
    rt.set_max_stack_size(STACK_LIMIT);
    let ctx = Context::full(&rt).map_err(|e| format!("QuickJS context: {e}"))?;

    let redactor = redact.filter(|s| s.enabled).map(|s| build_redactor(&s, &sink));
    let state: Shared = Rc::new(RefCell::new(State {
        sink: sink.clone(),
        next_call: 1,
        calls: HashMap::new(),
        streams: HashMap::new(),
        next_timer: 1,
        timers: HashMap::new(),
        chats: Chats::new(storage),
        redactor,
        restorers: HashMap::new(),
        answer_restorers: HashMap::new(),
    }));

    ctx.with(|ctx| -> Result<(), String> {
        install_host(&ctx, &state).map_err(|e| js_error(&ctx, e))?;
        load_bundle(&ctx).map_err(|e| js_error(&ctx, e))
    })?;
    // The module body has run; anything it queued runs now, before requests.
    drain_jobs(&rt, &sink);

    loop {
        drain_jobs(&rt, &sink);
        let wait = fire_timers(&ctx, &state, &sink);
        drain_jobs(&rt, &sink);

        let msg = match wait {
            Some(d) => match rx.recv_timeout(d) {
                Ok(m) => m,
                Err(RecvTimeoutError::Timeout) => continue,
                Err(RecvTimeoutError::Disconnected) => break,
            },
            None => match rx.recv() {
                Ok(m) => m,
                Err(_) => break,
            },
        };
        if matches!(msg, Inbound::Shutdown) {
            break;
        }
        ctx.with(|ctx| {
            if let Err(e) = handle(&ctx, &state, msg) {
                let message = js_error(&ctx, e);
                sink(Outbound::Log { level: "error".into(), message });
            }
        });
    }

    // Persistent handles must be released while the runtime is alive.
    let mut st = state.borrow_mut();
    st.calls.clear();
    st.streams.clear();
    st.restorers.clear();
    st.answer_restorers.clear();
    st.timers.clear();
    Ok(())
}

fn load_bundle(ctx: &Ctx<'_>) -> rquickjs::Result<()> {
    #[cfg(target_pointer_width = "64")]
    let module = {
        // SAFETY: the bytes are what `build.rs` wrote with this crate's own
        // QuickJS, and they are `'static`, as reading them as ROM data needs.
        unsafe { rquickjs::Module::load(ctx.clone(), BYTECODE)? }
    };
    #[cfg(not(target_pointer_width = "64"))]
    let module = {
        let _ = BYTECODE;
        rquickjs::Module::declare(ctx.clone(), "fl_pi_llm", SOURCE)?
    };
    let (_, promise) = module.eval()?;
    // Settled at once: the bundle has no top-level await. A rejection is the
    // module throwing, which is a broken bundle.
    promise.finish::<()>()
}

fn drain_jobs(rt: &Runtime, sink: &Sink) {
    loop {
        match rt.execute_pending_job() {
            Ok(true) => continue,
            Ok(false) => break,
            Err(e) => {
                let message = e.0.with(|ctx| js_error(&ctx, rquickjs::Error::Exception));
                sink(Outbound::Log { level: "error".into(), message: format!("Unhandled job error: {message}") });
            }
        }
    }
}

/// Runs every timer that is due, and says how long until the next one.
fn fire_timers(ctx: &Context, state: &Shared, sink: &Sink) -> Option<Duration> {
    let now = Instant::now();
    let due: Vec<u32> = {
        let st = state.borrow();
        let mut due: Vec<(Instant, u32)> =
            st.timers.iter().filter(|(_, t)| t.due <= now).map(|(id, t)| (t.due, *id)).collect();
        due.sort();
        due.into_iter().map(|(_, id)| id).collect()
    };
    for id in due {
        // Taken out while it runs: the callback may clear or add timers.
        let Some(timer) = state.borrow_mut().timers.remove(&id) else { continue };
        let cb = timer.cb.clone();
        if let Some(every) = timer.every {
            state.borrow_mut().timers.insert(id, Timer { due: now + every, every: timer.every, cb: timer.cb });
        }
        ctx.with(|ctx| {
            let res = cb.restore(&ctx).and_then(|f| f.call::<_, ()>(()));
            if let Err(e) = res {
                let message = js_error(&ctx, e);
                sink(Outbound::Log { level: "error".into(), message: format!("Timer error: {message}") });
            }
        });
    }
    let st = state.borrow();
    st.timers.values().map(|t| t.due.saturating_duration_since(Instant::now())).min()
}

fn handle<'js>(ctx: &Ctx<'js>, state: &Shared, msg: Inbound) -> rquickjs::Result<()> {
    match msg {
        Inbound::Request { req_id, method, payload } => {
            let fl: Object = ctx.globals().get("__fl")?;
            let dispatch: Function = fl.get("dispatch")?;
            let promise: Promise = dispatch.call((method, payload))?;
            let sink = state.borrow().sink.clone();
            let st = state.clone();
            let on_ok = Function::new(ctx.clone(), move |payload: String| {
                // What JS assembled from deltas still holds placeholders.
                let payload = match st.borrow().redactor.as_ref() {
                    Some(r) => r.restore_json(&payload),
                    None => payload,
                };
                sink(Outbound::Result { req_id, payload });
            })?;
            // `dispatch` never rejects; this only catches a broken bundle.
            let sink = state.borrow().sink.clone();
            let on_err = Function::new(ctx.clone(), move |ctx: Ctx<'_>, e: Value<'_>| {
                let error = describe(&ctx, e);
                let payload = serde_json::json!({ "ok": false, "error": error }).to_string();
                sink(Outbound::Result { req_id, payload });
            })?;
            let then: Function = promise.get("then")?;
            then.call::<_, ()>((rquickjs::function::This(promise), on_ok, on_err))?;
        }
        Inbound::Answer { call_id, result } => {
            let Some((ok, err)) = state.borrow_mut().calls.remove(&call_id) else { return Ok(()) };
            match result {
                Ok(v) => ok.restore(ctx)?.call::<_, ()>((v,))?,
                Err(e) => err.restore(ctx)?.call::<_, ()>((Exception::from_message(ctx.clone(), &e)?,))?,
            }
        }
        Inbound::BodyChunk { stream_id, mut chunk } => {
            if state.borrow().redactor.is_some() {
                let mut st = state.borrow_mut();
                let State { redactor, restorers, .. } = &mut *st;
                if let Some(redactor) = redactor.as_ref() {
                    // JSON, or SSE lines of it: a value put back is escaped.
                    chunk = restorers.entry(stream_id).or_insert_with(StreamRestorer::new_json).push(&chunk, redactor);
                }
            }
            let waiter = {
                let mut st = state.borrow_mut();
                let s = st.streams.entry(stream_id).or_default();
                match s.waiter.take() {
                    Some(w) => Some(w),
                    None => {
                        s.queue.push_back(chunk.clone());
                        None
                    }
                }
            };
            if let Some((ok, _)) = waiter {
                let arr = TypedArray::<u8>::new(ctx.clone(), chunk)?;
                ok.restore(ctx)?.call::<_, ()>((arr,))?;
            }
        }
        Inbound::BodyEnd { stream_id, error } => {
            let (tail, waiter) = {
                let mut st = state.borrow_mut();
                // What the restorer held back is the last of the body: a read
                // already waiting is handed it before the end.
                let State { redactor, restorers, .. } = &mut *st;
                let tail = match (redactor.as_ref(), restorers.remove(&stream_id)) {
                    (Some(redactor), Some(mut restorer)) => restorer.finish(redactor),
                    _ => Vec::new(),
                };
                let s = st.streams.entry(stream_id).or_default();
                s.ended = Some(error.clone());
                (tail, s.waiter.take())
            };
            // A body that ended in an error drops what was held back.
            if !tail.is_empty() && error.is_none() {
                match waiter {
                    Some((ok, _)) => {
                        let arr = TypedArray::<u8>::new(ctx.clone(), tail)?;
                        ok.restore(ctx)?.call::<_, ()>((arr,))?;
                    }
                    // Queued; `ended` is what the read after it finds.
                    None => {
                        state.borrow_mut().streams.entry(stream_id).or_default().queue.push_back(tail);
                    }
                }
            } else if let Some((ok, err)) = waiter {
                state.borrow_mut().streams.remove(&stream_id);
                match error {
                    None => ok.restore(ctx)?.call::<_, ()>((Value::new_null(ctx.clone()),))?,
                    Some(e) => err.restore(ctx)?.call::<_, ()>((Exception::from_message(ctx.clone(), &e)?,))?,
                }
            }
        }
        Inbound::Redact { settings } => {
            let sink = state.borrow().sink.clone();
            let mut st = state.borrow_mut();
            if let Some(r) = st.redactor.as_mut() {
                // What was hidden before stays restorable either way.
                match settings {
                    None => r.set_enabled(false),
                    // Checked by a settings page before it is stored; one that
                    // came in some other way leaves only itself out.
                    Some(s) => {
                        for e in r.apply_lenient(&s) {
                            sink(Outbound::Log { level: "error".into(), message: format!("redact rule not used: {e}") });
                        }
                    }
                }
            } else if let Some(s) = settings.filter(|s| s.enabled) {
                st.redactor = Some(build_redactor(&s, &sink));
            }
        }
        Inbound::Shutdown => {}
    }
    Ok(())
}

/// `globalThis.__host`, described in `js/src/web.js`.
fn install_host<'js>(ctx: &Ctx<'js>, state: &Shared) -> rquickjs::Result<()> {
    let host = Object::new(ctx.clone())?;

    let st = state.clone();
    host.set(
        "setTimer",
        Function::new(ctx.clone(), move |ctx: Ctx<'js>, ms: f64, cb: Function<'js>, repeat: Opt<bool>| {
            let mut s = st.borrow_mut();
            let id = s.next_timer;
            s.next_timer = s.next_timer.wrapping_add(1).max(1);
            let d = Duration::from_millis(if ms.is_finite() && ms > 0.0 { ms as u64 } else { 0 });
            let every = repeat.0.unwrap_or(false).then_some(d.max(Duration::from_millis(1)));
            s.timers.insert(id, Timer { due: Instant::now() + d, every, cb: Persistent::save(&ctx, cb) });
            id
        })?,
    )?;

    let st = state.clone();
    host.set(
        "clearTimer",
        Function::new(ctx.clone(), move |id: u32| {
            st.borrow_mut().timers.remove(&id);
        })?,
    )?;

    host.set(
        "randomBytes",
        Function::new(ctx.clone(), |ctx: Ctx<'js>, n: usize| {
            let mut buf = vec![0u8; n];
            getrandom::fill(&mut buf).map_err(|e| Exception::throw_message(&ctx, &e.to_string()))?;
            TypedArray::<u8>::new(ctx, buf)
        })?,
    )?;

    let st = state.clone();
    host.set(
        "log",
        Function::new(ctx.clone(), move |level: String, message: String| {
            let sink = st.borrow().sink.clone();
            sink(Outbound::Log { level, message });
        })?,
    )?;

    let st = state.clone();
    host.set(
        "emit",
        Function::new(ctx.clone(), move |payload: String| {
            let sink = st.borrow().sink.clone();
            let payload = restore_event(&payload, &mut st.borrow_mut());
            sink(Outbound::Event { payload });
        })?,
    )?;

    let st = state.clone();
    host.set(
        "notify",
        Function::new(ctx.clone(), move |name: String, payload: String| {
            let sink = st.borrow().sink.clone();
            sink(Outbound::Notify { name, payload });
        })?,
    )?;

    let st = state.clone();
    host.set(
        "call",
        Function::new(
            ctx.clone(),
            move |ctx: Ctx<'js>, name: String, payload: String, body: Opt<Value<'js>>| -> rquickjs::Result<Promise<'js>> {
                let body = match body.0 {
                    Some(v) if !v.is_undefined() && !v.is_null() => Some(bytes_of(&ctx, v)?),
                    _ => None,
                };
                let (promise, ok, err) = Promise::new(&ctx)?;
                let (call_id, sink) = {
                    let mut s = st.borrow_mut();
                    let id = s.next_call;
                    s.next_call += 1;
                    s.calls.insert(id, (Persistent::save(&ctx, ok), Persistent::save(&ctx, err)));
                    (id, s.sink.clone())
                };
                // A `fetch` body is the conversation: the one place a secret
                // leaves from. The host is told the kinds and counts hidden,
                // never a value: `{"github_token": 1}`. A tool call (and its
                // approval) is the model's, so it is acted on, and read, with
                // the values put back.
                let (payload, body, report) = match st.borrow_mut().redactor.as_mut() {
                    Some(r) if name == "tool" || name == "approve" => (restore_tool_args(&payload, r), body, None),
                    Some(r) if name == "fetch" => {
                        let body = body.map(|b| redact_body(&b, r));
                        (payload, body, r.take_report())
                    }
                    _ => (payload, body, None),
                };
                if let Some(report) = report {
                    let counts = serde_json::Value::Object(
                        report.into_iter().map(|(k, n)| (k, serde_json::Value::from(n))).collect(),
                    );
                    sink(Outbound::Notify { name: "redact".into(), payload: counts.to_string() });
                }
                sink(Outbound::HostCall { call_id, name, payload, body });
                // What a `fetch.cancel` before the answer names.
                if let Some(o) = promise.as_object() {
                    o.set("id", call_id)?;
                }
                Ok(promise)
            },
        )?,
    )?;

    let st = state.clone();
    host.set(
        "read",
        Function::new(ctx.clone(), move |ctx: Ctx<'js>, stream_id: u64| -> rquickjs::Result<Promise<'js>> {
            let (promise, ok, err) = Promise::new(&ctx)?;
            let mut s = st.borrow_mut();
            let stream = s.streams.entry(stream_id).or_default();
            if let Some(chunk) = stream.queue.pop_front() {
                drop(s);
                ok.call::<_, ()>((TypedArray::<u8>::new(ctx.clone(), chunk)?,))?;
            } else if let Some(end) = stream.ended.clone() {
                s.streams.remove(&stream_id);
                drop(s);
                match end {
                    None => ok.call::<_, ()>((Value::new_null(ctx.clone()),))?,
                    Some(e) => err.call::<_, ()>((Exception::from_message(ctx.clone(), &e)?,))?,
                }
            } else {
                stream.waiter = Some((Persistent::save(&ctx, ok), Persistent::save(&ctx, err)));
            }
            Ok(promise)
        })?,
    )?;

    install_db(ctx, &host, state)?;
    ctx.globals().set("__host", host)?;
    Ok(())
}

/// `__host.db*` and `__host.cache*`: the chats' SQLite databases and the
/// cache beside them (`rust/src/db.rs`), for `js/src/db.js`.
/// Synchronous; the statements are pi-durable's, each reading a page.
fn install_db<'js>(ctx: &Ctx<'js>, host: &Object<'js>, state: &Shared) -> rquickjs::Result<()> {
    let st = state.clone();
    host.set(
        "dbOpen",
        Function::new(ctx.clone(), move |ctx: Ctx<'js>, id: String| st.borrow_mut().chats.open(&id).map_err(|e| throw(&ctx, e)))?,
    )?;

    let st = state.clone();
    host.set(
        "dbClose",
        Function::new(ctx.clone(), move |h: u32| st.borrow_mut().chats.close(h))?,
    )?;

    let st = state.clone();
    host.set(
        "dbExec",
        Function::new(ctx.clone(), move |ctx: Ctx<'js>, h: u32, sql: String| -> rquickjs::Result<()> {
            let s = st.borrow();
            let conn = s.chats.get(h).map_err(|e| throw(&ctx, e))?;
            conn.execute_batch(&sql).map_err(|e| throw(&ctx, e.to_string()))
        })?,
    )?;

    // `mode`: 0 runs, 1 returns the first row or undefined, 2 every row, 3 runs and returns changed row count.
    let st = state.clone();
    host.set(
        "dbQuery",
        Function::new(
            ctx.clone(),
            move |ctx: Ctx<'js>, h: u32, sql: String, params: Array<'js>, mode: u8| -> rquickjs::Result<Value<'js>> {
                let mut params = params.iter::<Value>().map(|v| sql_value(&ctx, v?)).collect::<rquickjs::Result<Vec<_>>>()?;
                let s = st.borrow();
                // A chat is stored with the values put back: a placeholder's
                // nonce lives only as long as this process.
                if let Some(r) = s.redactor.as_ref() {
                    for p in &mut params {
                        if let SqlValue::Text(t) = p {
                            *t = r.restore_stored(t);
                        }
                    }
                }
                let conn = s.chats.get(h).map_err(|e| throw(&ctx, e))?;
                query(&ctx, conn, &sql, params, mode).map_err(|e| match e {
                    QueryError::Sql(e) => throw(&ctx, e.to_string()),
                    QueryError::Js(e) => e,
                })
            },
        )?,
    )?;

    let st = state.clone();
    host.set(
        "dbList",
        Function::new(ctx.clone(), move |ctx: Ctx<'js>| -> rquickjs::Result<Array<'js>> {
            let chats = st.borrow().chats.list().map_err(|e| throw(&ctx, e))?;
            let out = Array::new(ctx.clone())?;
            for (i, c) in chats.into_iter().enumerate() {
                let o = Object::new(ctx.clone())?;
                o.set("id", c.id)?;
                o.set("createdAt", c.created_at_ms as f64)?;
                o.set("modifiedAt", c.modified_at_ms as f64)?;
                out.set(i, o)?;
            }
            Ok(out)
        })?,
    )?;

    let st = state.clone();
    host.set(
        "cacheGet",
        Function::new(ctx.clone(), move |ctx: Ctx<'js>, key: String| st.borrow_mut().chats.cache_get(&key).map_err(|e| throw(&ctx, e)))?,
    )?;

    let st = state.clone();
    host.set(
        "cacheSet",
        Function::new(ctx.clone(), move |ctx: Ctx<'js>, key: String, value: Option<String>| {
            st.borrow_mut().chats.cache_set(&key, value.as_deref()).map_err(|e| throw(&ctx, e))
        })?,
    )?;

    let st = state.clone();
    host.set(
        "dbRemove",
        Function::new(ctx.clone(), move |ctx: Ctx<'js>, id: String| st.borrow().chats.remove(&id).map_err(|e| throw(&ctx, e)))?,
    )?;
    Ok(())
}

enum QueryError {
    Sql(rusqlite::Error),
    Js(rquickjs::Error),
}

impl From<rusqlite::Error> for QueryError {
    fn from(e: rusqlite::Error) -> Self {
        Self::Sql(e)
    }
}

impl From<rquickjs::Error> for QueryError {
    fn from(e: rquickjs::Error) -> Self {
        Self::Js(e)
    }
}

fn query<'js>(ctx: &Ctx<'js>, conn: &rusqlite::Connection, sql: &str, params: Vec<SqlValue>, mode: u8) -> Result<Value<'js>, QueryError> {
    let mut stmt = conn.prepare_cached(sql)?;
    if mode == 0 {
        stmt.execute(rusqlite::params_from_iter(params))?;
        return Ok(Value::new_undefined(ctx.clone()));
    }
    if mode == 3 {
        let n = stmt.execute(rusqlite::params_from_iter(params))?;
        return Ok(Value::new_number(ctx.clone(), n as f64));
    }
    let names: Vec<String> = stmt.column_names().into_iter().map(String::from).collect();
    let mut rows = stmt.query(rusqlite::params_from_iter(params))?;
    let out = Array::new(ctx.clone())?;
    let mut n = 0;
    while let Some(row) = rows.next()? {
        let o = Object::new(ctx.clone())?;
        for (i, name) in names.iter().enumerate() {
            o.set(name.as_str(), js_value(ctx, row.get_ref(i)?)?)?;
        }
        if mode == 1 {
            return Ok(o.into_value());
        }
        out.set(n, o)?;
        n += 1;
    }
    Ok(if mode == 1 { Value::new_undefined(ctx.clone()) } else { out.into_value() })
}

/// A binding, as `node:sqlite` takes one: an integral number binds as an
/// integer, so `STRICT` integer columns accept it.
fn sql_value<'js>(ctx: &Ctx<'js>, v: Value<'js>) -> rquickjs::Result<SqlValue> {
    if v.is_null() || v.is_undefined() {
        return Ok(SqlValue::Null);
    }
    if let Some(i) = v.as_int() {
        return Ok(SqlValue::Integer(i.into()));
    }
    if let Some(f) = v.as_float() {
        const SAFE: f64 = 9_007_199_254_740_991.0;
        return Ok(if f.fract() == 0.0 && f.abs() <= SAFE { SqlValue::Integer(f as i64) } else { SqlValue::Real(f) });
    }
    if let Some(b) = v.as_bool() {
        return Ok(SqlValue::Integer(b.into()));
    }
    if let Some(s) = v.as_string() {
        return Ok(SqlValue::Text(s.to_string()?));
    }
    if let Some(b) = v.as_big_int() {
        return Ok(SqlValue::Integer(b.clone().to_i64()?));
    }
    if let Ok(arr) = TypedArray::<u8>::from_value(v.clone()) {
        // SAFETY: copied out before any JavaScript runs again.
        return Ok(SqlValue::Blob(unsafe { arr.as_slice() }.to_vec()));
    }
    Err(Exception::throw_type(ctx, &format!("cannot bind a {} to SQL", v.type_name())))
}

/// A column as `node:sqlite` reads one: an integer is a number.
fn js_value<'js>(ctx: &Ctx<'js>, v: ValueRef<'_>) -> rquickjs::Result<Value<'js>> {
    Ok(match v {
        ValueRef::Null => Value::new_null(ctx.clone()),
        ValueRef::Integer(i) => match i32::try_from(i) {
            Ok(i) => Value::new_int(ctx.clone(), i),
            Err(_) => Value::new_number(ctx.clone(), i as f64),
        },
        ValueRef::Real(f) => Value::new_number(ctx.clone(), f),
        ValueRef::Text(t) => rquickjs::String::from_str(ctx.clone(), &String::from_utf8_lossy(t))?.into_value(),
        ValueRef::Blob(b) => TypedArray::<u8>::new(ctx.clone(), b.to_vec())?.into_value(),
    })
}

fn throw(ctx: &Ctx<'_>, message: impl AsRef<str>) -> rquickjs::Error {
    Exception::throw_message(ctx, message.as_ref())
}

/// The bytes of a `Uint8Array`, `ArrayBuffer` or string.
fn bytes_of<'js>(ctx: &Ctx<'js>, v: Value<'js>) -> rquickjs::Result<Vec<u8>> {
    if let Some(s) = v.as_string() {
        return Ok(s.to_string()?.into_bytes());
    }
    if let Ok(arr) = TypedArray::<u8>::from_value(v.clone()) {
        // SAFETY: copied out before any JavaScript runs again.
        return Ok(unsafe { arr.as_slice() }.to_vec());
    }
    if let Some(buf) = rquickjs::ArrayBuffer::from_value(v) {
        // SAFETY: copied out before any JavaScript runs again.
        if let Some(bytes) = unsafe { buf.as_bytes() } {
            return Ok(bytes.to_vec());
        }
    }
    Err(Exception::throw_message(ctx, "body must be a Uint8Array, ArrayBuffer or string"))
}

/// A readable message for an error, with the stack when JavaScript threw one.
fn js_error(ctx: &Ctx<'_>, e: rquickjs::Error) -> String {
    if matches!(e, rquickjs::Error::Exception) {
        describe(ctx, ctx.catch())
    } else {
        e.to_string()
    }
}

fn describe(_ctx: &Ctx<'_>, v: Value<'_>) -> String {
    if let Some(ex) = v.as_exception() {
        let msg = ex.message().unwrap_or_default();
        return match ex.stack() {
            Some(stack) if !stack.is_empty() => format!("{msg}\n{stack}"),
            _ => msg,
        };
    }
    if let Some(s) = v.as_string() {
        return s.to_string().unwrap_or_default();
    }
    format!("{v:?}")
}

/// A request body with every secret replaced.
///
/// A JSON body is walked string by string rather than matched as one text: a
/// rule run over the document can begin inside one string and end in the
/// next — a URL rule's password class stops at an `@`, and the next `@` in
/// the document may be in another message — and replacing across that boundary
/// would leave a document the endpoint cannot read. A body that is not JSON is
/// still text a secret can be in, and is matched as it is.
fn redact_body(body: &[u8], redactor: &mut Redactor) -> Vec<u8> {
    let Ok(text) = std::str::from_utf8(body) else {
        // Not text: nothing here can recognise a secret in it either.
        return body.to_vec();
    };
    let Ok(mut doc) = serde_json::from_str::<serde_json::Value>(text) else {
        return redactor.redact(text).into_bytes();
    };
    // Unchanged is sent as it arrived: a body written a particular way — key
    // order, spacing, escapes — is the caller's, and nothing here should
    // rewrite it for nothing.
    if !redact_value(&mut doc, redactor) {
        return body.to_vec();
    }
    serde_json::to_vec(&doc).unwrap_or_else(|_| body.to_vec())
}

/// Redacts every string in [value], and says whether any of them changed.
fn redact_value(value: &mut serde_json::Value, redactor: &mut Redactor) -> bool {
    match value {
        serde_json::Value::String(s) => {
            let redacted = redactor.redact(s);
            let changed = redacted != *s;
            *s = redacted;
            changed
        }
        serde_json::Value::Array(a) => a.iter_mut().fold(false, |any, v| redact_value(v, redactor) | any),
        serde_json::Value::Object(o) => o.values_mut().fold(false, |any, v| redact_value(v, redactor) | any),
        _ => false,
    }
}

/// A redactor for [settings], leaving out a custom rule that does not compile
/// rather than starting with none: a stored typo must not cost the Agent.
fn build_redactor(settings: &Settings, sink: &Sink) -> Redactor {
    let (redactor, errors) = Redactor::lenient(settings);
    for e in errors {
        sink(Outbound::Log { level: "error".into(), message: format!("redact rule not used: {e}") });
    }
    redactor
}

/// A tool call's arguments with every placeholder put back, or unchanged when
/// that would leave JSON that does not parse.
fn restore_tool_args(payload: &str, redactor: &Redactor) -> String {
    let restored = redactor.restore_json(payload);
    if restored == payload || serde_json::from_str::<serde_json::Value>(&restored).is_err() {
        return payload.to_string();
    }
    restored
}

/// One event from the engine with its placeholders put back: a streamed delta
/// through its content block's restorer, anything else whole.
fn restore_event(payload: &str, state: &mut State) -> String {
    let Some(redactor) = state.redactor.as_ref() else { return payload.to_string() };
    let Ok(mut event) = serde_json::from_str::<serde_json::Value>(payload) else {
        return redactor.restore_json(payload);
    };
    let Some(session) = event["sessionId"].as_str().map(str::to_string) else {
        return redactor.restore_json(payload);
    };
    // `{sessionId, event: {type, event?: {type, contentIndex, delta}}}`.
    let outer = event["event"]["type"].as_str().unwrap_or_default();
    if matches!(outer, "message_start" | "message_end" | "run_end") {
        // What a restorer still held is in the whole message this carries.
        state.answer_restorers.retain(|(s, _), _| *s != session);
    }
    let inner = &event["event"]["event"];
    let streamed = matches!(inner["type"].as_str(), Some("text_delta" | "thinking_delta"));
    let (Some(index), Some(delta), true) = (inner["contentIndex"].as_u64(), inner["delta"].as_str(), streamed) else {
        return redactor.restore_json(payload);
    };
    let restorer = state.answer_restorers.entry((session, index)).or_default();
    let restored = String::from_utf8_lossy(&restorer.push(delta.as_bytes(), redactor)).into_owned();
    event["event"]["event"]["delta"] = serde_json::Value::String(restored);
    event.to_string()
}
