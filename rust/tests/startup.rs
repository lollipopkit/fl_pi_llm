use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use fl_pi_llm::engine::{Engine, Inbound, Outbound};

#[test]
#[ignore = "timing, not a check: cargo test --release --test startup -- --ignored --nocapture"]
fn startup_time() {
    let t = Instant::now();
    let (tx, rx) = mpsc::channel();
    let tx = Mutex::new(tx);
    let e = Engine::spawn(Arc::new(move |o| { let _ = tx.lock().unwrap().send(o); })).unwrap();
    e.send(Inbound::Request { req_id: 1, method: "runtime.info".into(), payload: "{}".into() });
    loop {
        if let Outbound::Result { .. } = rx.recv().unwrap() { break; }
    }
    eprintln!("engine start to first answer: {:?}", t.elapsed());
}
