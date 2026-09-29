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
    Context, Ctx, Exception, Function, Object, Persistent, Promise, Runtime, TypedArray, Value,
};

/// The bundle built from `js/`: pi-agent-core, pi-ai and the Web layer, as
/// QuickJS bytecode compiled by `build.rs`. Empty on 32-bit targets.
static BYTECODE: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/fl_pi_llm.qbc"));

/// The same bundle as source, for the targets that have no bytecode.
#[cfg(not(target_pointer_width = "64"))]
const SOURCE: &str = include_str!("../js/fl_pi_llm.js");

/// QuickJS heap ceiling. A conversation is text; a runaway is a bug.
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
    pub fn spawn(sink: Sink) -> std::io::Result<Self> {
        let (tx, rx) = mpsc::channel();
        let thread = std::thread::Builder::new()
            .name("fl_pi_llm".into())
            // QuickJS runs on this thread's stack; the limit above has to fit.
            .stack_size(STACK_LIMIT * 2)
            .spawn(move || {
                if let Err(e) = run(rx, sink.clone()) {
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
}

type Shared = Rc<RefCell<State>>;

fn run(rx: Receiver<Inbound>, sink: Sink) -> Result<(), String> {
    let rt = Runtime::new().map_err(|e| format!("QuickJS runtime: {e}"))?;
    rt.set_memory_limit(MEMORY_LIMIT);
    rt.set_max_stack_size(STACK_LIMIT);
    let ctx = Context::full(&rt).map_err(|e| format!("QuickJS context: {e}"))?;

    let state: Shared = Rc::new(RefCell::new(State {
        sink: sink.clone(),
        next_call: 1,
        calls: HashMap::new(),
        streams: HashMap::new(),
        next_timer: 1,
        timers: HashMap::new(),
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
            let on_ok = Function::new(ctx.clone(), move |payload: String| {
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
        Inbound::BodyChunk { stream_id, chunk } => {
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
            let waiter = {
                let mut st = state.borrow_mut();
                let s = st.streams.entry(stream_id).or_default();
                s.ended = Some(error.clone());
                s.waiter.take()
            };
            if let Some((ok, err)) = waiter {
                state.borrow_mut().streams.remove(&stream_id);
                match error {
                    None => ok.restore(ctx)?.call::<_, ()>((Value::new_null(ctx.clone()),))?,
                    Some(e) => err.restore(ctx)?.call::<_, ()>((Exception::from_message(ctx.clone(), &e)?,))?,
                }
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
                sink(Outbound::HostCall { call_id, name, payload, body });
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

    ctx.globals().set("__host", host)?;
    Ok(())
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
