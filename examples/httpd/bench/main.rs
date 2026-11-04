// SPDX-License-Identifier: MIT
// The server of examples/httpd/httpd.pas in Rust, for the benchmark (run.sh): the standard library only, a thread
// per connection, the same minimal HTTP/1.1 handling, routes and bodies.
// build: rustc -O -C target-cpu=native main.rs      usage: main [PORT]   (default 8080)
use std::io::{self, BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::atomic::{AtomicU64, Ordering};
use std::thread;
use std::time::Duration;

static REQUESTS: AtomicU64 = AtomicU64::new(0);
static BYTES: AtomicU64 = AtomicU64::new(0);

fn send(out: &mut TcpStream, code: u16, ctype: &str, body: &str, keep: bool) -> io::Result<()> {
    let reason = match code {
        200 => "OK",
        404 => "Not Found",
        _ => "Bad Request",
    };
    let conn = if keep { "keep-alive" } else { "close" };
    let msg = format!(
        "HTTP/1.1 {code} {reason}\r\nContent-Type: {ctype}\r\nContent-Length: {}\r\nConnection: {conn}\r\n\r\n{body}",
        body.len()
    );
    REQUESTS.fetch_add(1, Ordering::Relaxed);
    BYTES.fetch_add(body.len() as u64, Ordering::Relaxed);
    out.write_all(msg.as_bytes())
}

fn squares(n: u32) -> String {
    let items: Vec<String> = (1..=n).map(|i| (i * i).to_string()).collect();
    format!("{{\"n\":{n},\"squares\":[{}]}}\n", items.join(","))
}

fn route(out: &mut TcpStream, target: &str, keep: bool) -> io::Result<()> {
    let (path, query) = target.split_once('?').unwrap_or((target, ""));
    match path {
        "/" => send(out, 200, "text/plain", "Hello from Better Pascal\n", keep),
        "/json" => {
            let n = query.split('&').find_map(|kv| kv.strip_prefix("n=")).unwrap_or("10");
            match n.parse::<u32>() {
                Ok(n) if n <= 1000 => send(out, 200, "application/json", &squares(n), keep),
                _ => send(out, 400, "text/plain", "n must be 0..1000\n", keep),
            }
        }
        "/stats" => {
            let body = format!(
                "{{\"requests\":{},\"bytes\":{}}}\n",
                REQUESTS.load(Ordering::Relaxed),
                BYTES.load(Ordering::Relaxed)
            );
            send(out, 200, "application/json", &body, keep)
        }
        _ => send(out, 404, "text/plain", "Not Found\n", keep),
    }
}

fn serve(stream: TcpStream) -> io::Result<()> {
    stream.set_read_timeout(Some(Duration::from_secs(2)))?;
    let mut out = stream.try_clone()?;
    let mut input = BufReader::new(stream);
    loop {
        let mut line = String::new();
        if input.read_line(&mut line)? == 0 {
            return Ok(());
        }
        let parts: Vec<&str> = line.trim_end().split(' ').collect();
        let mut ok = parts.len() == 3
            && parts[1].starts_with('/')
            && (parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0");
        let (mut len, mut conn) = (0usize, String::new());
        loop {
            let mut header = String::new();
            if input.read_line(&mut header)? == 0 {
                return Ok(());
            }
            let header = header.trim_end();
            if header.is_empty() {
                break;
            }
            match header.split_once(':') {
                Some((name, value)) if !name.is_empty() => match name.trim().to_ascii_lowercase().as_str() {
                    "content-length" => match value.trim().parse() {
                        Ok(n) => len = n,
                        Err(_) => ok = false,
                    },
                    "connection" => conn = value.trim().to_ascii_lowercase(),
                    "transfer-encoding" => ok = false,
                    _ => {}
                },
                _ => ok = false,
            }
        }
        if !ok {
            return send(&mut out, 400, "text/plain", "Bad Request\n", false);
        }
        let mut body = vec![0u8; len];
        input.read_exact(&mut body)?;
        let keep = if parts[2] == "HTTP/1.1" { !conn.contains("close") } else { conn.contains("keep-alive") };
        route(&mut out, parts[1], keep)?;
        if !keep {
            return Ok(());
        }
    }
}

fn main() {
    let port = std::env::args().nth(1).unwrap_or_else(|| "8080".to_string());
    let listener = TcpListener::bind(format!("0.0.0.0:{port}")).expect("bind");
    for stream in listener.incoming().flatten() {
        thread::spawn(move || serve(stream));
    }
}
