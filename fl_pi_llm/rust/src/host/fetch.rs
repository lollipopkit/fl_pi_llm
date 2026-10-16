//! The network for the Rust host: the `fetch` host call `js/src/web.js` makes,
//! answered by a [`Fetch`]. [`ReqwestFetch`] (feature `reqwest`) is one.

use tokio::sync::mpsc;

use super::BoxFuture;

/// A request as pi's `fetch` makes it.
#[derive(Debug, Clone)]
pub struct FetchRequest {
    pub url: String,
    pub method: String,
    pub headers: Vec<(String, String)>,
    pub body: Option<Vec<u8>>,
}

/// The response head; the body arrives on [`FetchResponse::body`], ending
/// with the channel closing (`Err` when it failed). Dropping the receiver
/// cancels the request.
pub struct FetchResponse {
    pub status: u16,
    pub status_text: String,
    /// Without `content-length`, `content-encoding` and `transfer-encoding`:
    /// the body is handed over decoded.
    pub headers: Vec<(String, String)>,
    pub body: mpsc::Receiver<Result<Vec<u8>, String>>,
}

pub trait Fetch: Send + Sync {
    fn fetch(&self, req: FetchRequest) -> BoxFuture<'_, Result<FetchResponse, String>>;
}

/// Where requests may go: HTTPS anywhere, plain HTTP to this machine or to an
/// origin listed in `insecure_origins` (`http://host:port`, a provider the
/// operator allowed it for). Every other scheme is refused.
pub fn fetch_allowed(url: &str, insecure_origins: &[String]) -> bool {
    let Some((scheme, rest)) = url.split_once("://") else { return false };
    match scheme.to_ascii_lowercase().as_str() {
        "https" => true,
        "http" => {
            let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
            // Userinfo is never part of where a request goes.
            if authority.contains('@') {
                return false;
            }
            let host = match authority.strip_prefix('[') {
                Some(v6) => v6.split(']').next().unwrap_or(""),
                None => authority.rsplit_once(':').map_or(authority, |(h, _)| h),
            }
            .to_ascii_lowercase();
            if host == "localhost" || host.parse::<std::net::IpAddr>().is_ok_and(|ip| ip.is_loopback()) {
                return true;
            }
            let origin = format!("http://{}", authority.to_ascii_lowercase());
            insecure_origins.iter().any(|o| o.trim_end_matches('/').eq_ignore_ascii_case(&origin))
        }
        _ => false,
    }
}

/// Headers that describe the body as it came off the wire.
pub(crate) const HOP_HEADERS: [&str; 3] = ["content-length", "content-encoding", "transfer-encoding"];

#[cfg(feature = "reqwest")]
pub use self::reqwest_fetch::ReqwestFetch;

#[cfg(feature = "reqwest")]
mod reqwest_fetch {
    use std::sync::{Arc, RwLock};

    use super::*;

    /// [`Fetch`] over a `reqwest::Client` the caller built — its TLS, proxy
    /// and timeouts are what apply. Redirects must not be followed by that
    /// client (`redirect::Policy::none()`): [`fetch_allowed`] judged this
    /// address, not wherever it sends the request on to, key and all.
    pub struct ReqwestFetch {
        client: reqwest::Client,
        insecure: Arc<RwLock<Vec<String>>>,
    }

    impl ReqwestFetch {
        pub fn new(client: reqwest::Client) -> Self {
            Self { client, insecure: Arc::default() }
        }

        /// Replaces the plain-HTTP origins requests may go to.
        pub fn set_insecure_origins(&self, origins: Vec<String>) {
            *self.insecure.write().unwrap() = origins;
        }
    }

    impl Fetch for ReqwestFetch {
        fn fetch(&self, req: FetchRequest) -> BoxFuture<'_, Result<FetchResponse, String>> {
            Box::pin(async move {
                if !fetch_allowed(&req.url, &self.insecure.read().unwrap()) {
                    return Err(format!("fetch refused: {} is plain http off this machine", req.url));
                }
                let method = reqwest::Method::from_bytes(req.method.as_bytes()).map_err(|e| e.to_string())?;
                let mut b = self.client.request(method, &req.url);
                for (k, v) in &req.headers {
                    if k.eq_ignore_ascii_case("host") || k.eq_ignore_ascii_case("content-length") {
                        continue;
                    }
                    b = b.header(k, v);
                }
                if let Some(body) = req.body {
                    b = b.body(body);
                }
                let mut res = b.send().await.map_err(|e| format!("fetch failed: {e}"))?;
                let headers = res
                    .headers()
                    .iter()
                    .filter(|(k, _)| !HOP_HEADERS.contains(&k.as_str()))
                    .map(|(k, v)| (k.as_str().to_string(), String::from_utf8_lossy(v.as_bytes()).into_owned()))
                    .collect();
                let status = res.status();
                let (tx, rx) = mpsc::channel(16);
                tokio::spawn(async move {
                    loop {
                        match res.chunk().await {
                            Ok(Some(c)) => {
                                if tx.send(Ok(c.to_vec())).await.is_err() {
                                    return; // cancelled: dropping `res` ends the request
                                }
                            }
                            Ok(None) => return,
                            Err(e) => {
                                let _ = tx.send(Err(e.to_string())).await;
                                return;
                            }
                        }
                    }
                });
                Ok(FetchResponse {
                    status: status.as_u16(),
                    status_text: status.canonical_reason().unwrap_or("").to_string(),
                    headers,
                    body: rx,
                })
            })
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn plain_http_only_to_this_machine_or_an_allowed_origin() {
        let allowed = vec!["http://10.0.0.2:8080".to_string()];
        assert!(fetch_allowed("https://api.openai.com/v1", &[]));
        assert!(fetch_allowed("http://localhost:11434/v1", &[]));
        assert!(fetch_allowed("http://127.0.0.1:11434/v1", &[]));
        assert!(fetch_allowed("http://[::1]:11434/v1", &[]));
        assert!(fetch_allowed("http://10.0.0.2:8080/v1/chat", &allowed));
        assert!(!fetch_allowed("http://10.0.0.2:8081/v1", &allowed));
        assert!(!fetch_allowed("http://10.0.0.3/v1", &[]));
        assert!(!fetch_allowed("http://127.0.0.1@10.0.0.3/v1", &[]));
        assert!(!fetch_allowed("file:///etc/passwd", &[]));
        assert!(!fetch_allowed("ftp://x", &[]));
    }
}
