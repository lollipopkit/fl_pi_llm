//! fl_pi_llm: pi-durable and pi-ai on QuickJS, bridged to Dart ([`api`])
//! or hosted by a Rust program ([`host`]).

#[cfg(feature = "frb")]
pub mod api;
pub mod db;
pub mod engine;
pub mod mcp;
pub mod memory;
pub mod skills;
#[cfg(feature = "frb")]
mod frb_generated;
#[cfg(feature = "host")]
pub mod host;
