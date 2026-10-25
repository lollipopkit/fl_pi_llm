//! What Dart sees. Kept thin: the protocol is JSON strings in both directions,
//! decoded on the Dart side, so a change to what pi sends is a Dart change and
//! never a regenerated bridge.

use std::sync::OnceLock;

pub mod mcp;
pub mod memory;
pub mod skills;

/// The chats kept under [dir], encrypted with [key], where [needle] was said
/// by the user or the model, ignoring case. Off the engine, beside it.
pub fn search_chats(dir: String, key: Option<Vec<u8>>, needle: String) -> anyhow::Result<Vec<String>> {
    crate::db::search(&storage(dir, key)?, &needle).map_err(anyhow::Error::msg)
}

fn storage(dir: String, key: Option<Vec<u8>>) -> anyhow::Result<crate::db::Storage> {
    let key = key.map(|k| crate::db::Key::new(&k)).transpose().map_err(anyhow::Error::msg)?;
    Ok(crate::db::Storage { root: dir.into(), key })
}

use flutter_rust_bridge::frb;

use crate::engine::{Engine, Inbound, Outbound};
use crate::frb_generated::StreamSink;

/// What a [HostMessage] is.
pub enum HostMessageKind {
    /// [HostMessage::id] is the request; [HostMessage::payload] its JSON result.
    Result,
    /// [HostMessage::id] is the call to answer; [HostMessage::name] what to do.
    HostCall,
    /// [HostMessage::name] happened; no answer.
    Notify,
    /// [HostMessage::payload] is an event, as JSON.
    Event,
    /// [HostMessage::name] is the level.
    Log,
    /// The engine is gone; [HostMessage::payload] says why.
    Fatal,
}

/// A message from the engine. A flat struct rather than an enum with fields,
/// so the Dart side needs no generated sealed classes.
pub struct HostMessage {
    pub kind: HostMessageKind,
    pub id: i64,
    pub name: String,
    pub payload: String,
    pub body: Option<Vec<u8>>,
}

impl From<Outbound> for HostMessage {
    fn from(o: Outbound) -> Self {
        let m = |kind, id: u64, name: String, payload: String, body| Self { kind, id: id as i64, name, payload, body };
        match o {
            Outbound::Result { req_id, payload } => m(HostMessageKind::Result, req_id, String::new(), payload, None),
            Outbound::HostCall { call_id, name, payload, body } => m(HostMessageKind::HostCall, call_id, name, payload, body),
            Outbound::Notify { name, payload } => m(HostMessageKind::Notify, 0, name, payload, None),
            Outbound::Event { payload } => m(HostMessageKind::Event, 0, String::new(), payload, None),
            Outbound::Log { level, message } => m(HostMessageKind::Log, 0, level, message, None),
            Outbound::Fatal { message } => m(HostMessageKind::Fatal, 0, String::new(), message, None),
        }
    }
}

/// One JavaScript runtime. Dropped, it shuts down.
///
/// Created empty and started by [LlmEngine::start], because the bridge turns a
/// function taking a sink into one returning a stream — and a constructor that
/// did both would hand Dart the stream and lose the engine.
#[frb(opaque)]
pub struct LlmEngine {
    inner: OnceLock<Engine>,
}

impl LlmEngine {
    #[frb(sync)]
    pub fn new() -> LlmEngine {
        Self { inner: OnceLock::new() }
    }

    /// Starts the runtime, keeping chats under [dir], encrypted with [key]
    /// (32 bytes) when there is one. Everything it says arrives on [sink], in
    /// order.
    #[frb(sync)]
    pub fn start(&self, dir: String, key: Option<Vec<u8>>, sink: StreamSink<HostMessage>) -> anyhow::Result<()> {
        let engine = Engine::spawn(
            std::sync::Arc::new(move |o: Outbound| {
                let _ = sink.add(o.into());
            }),
            Some(storage(dir, key)?),
        )?;
        self.inner.set(engine).map_err(|_| anyhow::anyhow!("already started"))
    }

    fn send(&self, msg: Inbound) -> bool {
        self.inner.get().is_some_and(|e| e.send(msg))
    }

    /// Asks `__fl.dispatch(method, payload)`; answered by a result message.
    #[frb(sync)]
    pub fn request(&self, req_id: i64, method: String, payload: String) -> bool {
        self.send(Inbound::Request { req_id: req_id as u64, method, payload })
    }

    /// Answers a host call: [error] when set, [payload] otherwise.
    #[frb(sync)]
    pub fn answer(&self, call_id: i64, payload: String, error: Option<String>) -> bool {
        let result = match error {
            Some(e) => Err(e),
            None => Ok(payload),
        };
        self.send(Inbound::Answer { call_id: call_id as u64, result })
    }

    /// A chunk of a response body.
    #[frb(sync)]
    pub fn push_body(&self, stream_id: i64, chunk: Vec<u8>) -> bool {
        self.send(Inbound::BodyChunk { stream_id: stream_id as u64, chunk })
    }

    /// The end of a response body.
    #[frb(sync)]
    pub fn end_body(&self, stream_id: i64, error: Option<String>) -> bool {
        self.send(Inbound::BodyEnd { stream_id: stream_id as u64, error })
    }
}
