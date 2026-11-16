//! lab_serde.rs -- AUDIT-ONLY stand-in for the `serde_json` crate, host lab
//! only. Implements exactly the `Value` API surface that the plan's
//! src/policy.rs uses: `from_slice`, `Value::{Null,Bool,Number,String,Array,
//! Object}`, `Value::get(&str) -> Option<&Value>`. The DEVICE build links the
//! real `libserde_json` via soong (plan §6); the loader semantics exercised
//! here (parse ok / parse fail / key absent / string / number / other) are
//! the ones policy.rs branches on. Strict RFC 8259 subset; rejects garbage.

use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Null,
    Bool(bool),
    Number(f64),
    String(String),
    Array(Vec<Value>),
    Object(BTreeMap<String, Value>),
}

impl Value {
    pub fn get(&self, key: &str) -> Option<&Value> {
        match self {
            Value::Object(m) => m.get(key),
            _ => None,
        }
    }
}

#[derive(Debug)]
pub struct Error(pub String);

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

pub fn from_slice(bytes: &[u8]) -> Result<Value, Error> {
    let s = std::str::from_utf8(bytes).map_err(|_| Error("not utf-8".into()))?;
    let mut p = P { b: s.as_bytes(), i: 0 };
    p.ws();
    let v = p.value()?;
    p.ws();
    if p.i != p.b.len() {
        return Err(Error("trailing characters".into()));
    }
    Ok(v)
}

struct P<'a> {
    b: &'a [u8],
    i: usize,
}

impl<'a> P<'a> {
    fn ws(&mut self) {
        while self.i < self.b.len() && matches!(self.b[self.i], b' ' | b'\t' | b'\n' | b'\r') {
            self.i += 1;
        }
    }
    fn peek(&self) -> Option<u8> {
        self.b.get(self.i).copied()
    }
    fn value(&mut self) -> Result<Value, Error> {
        match self.peek() {
            Some(b'{') => self.object(),
            Some(b'[') => self.array(),
            Some(b'"') => Ok(Value::String(self.string()?)),
            Some(b't') => self.lit(b"true", Value::Bool(true)),
            Some(b'f') => self.lit(b"false", Value::Bool(false)),
            Some(b'n') => self.lit(b"null", Value::Null),
            Some(c) if c == b'-' || c.is_ascii_digit() => self.number(),
            _ => Err(Error("expected value".into())),
        }
    }
    fn lit(&mut self, word: &[u8], v: Value) -> Result<Value, Error> {
        if self.b[self.i..].starts_with(word) {
            self.i += word.len();
            Ok(v)
        } else {
            Err(Error("bad literal".into()))
        }
    }
    fn object(&mut self) -> Result<Value, Error> {
        self.i += 1; // {
        let mut m = BTreeMap::new();
        self.ws();
        if self.peek() == Some(b'}') {
            self.i += 1;
            return Ok(Value::Object(m));
        }
        loop {
            self.ws();
            if self.peek() != Some(b'"') {
                return Err(Error("expected key".into()));
            }
            let k = self.string()?;
            self.ws();
            if self.peek() != Some(b':') {
                return Err(Error("expected ':'".into()));
            }
            self.i += 1;
            self.ws();
            let v = self.value()?;
            m.insert(k, v);
            self.ws();
            match self.peek() {
                Some(b',') => {
                    self.i += 1;
                }
                Some(b'}') => {
                    self.i += 1;
                    return Ok(Value::Object(m));
                }
                _ => return Err(Error("expected ',' or '}'".into())),
            }
        }
    }
    fn array(&mut self) -> Result<Value, Error> {
        self.i += 1; // [
        let mut a = Vec::new();
        self.ws();
        if self.peek() == Some(b']') {
            self.i += 1;
            return Ok(Value::Array(a));
        }
        loop {
            self.ws();
            a.push(self.value()?);
            self.ws();
            match self.peek() {
                Some(b',') => {
                    self.i += 1;
                }
                Some(b']') => {
                    self.i += 1;
                    return Ok(Value::Array(a));
                }
                _ => return Err(Error("expected ',' or ']'".into())),
            }
        }
    }
    fn string(&mut self) -> Result<String, Error> {
        self.i += 1; // opening quote
        let mut out = String::new();
        loop {
            match self.peek() {
                None => return Err(Error("unterminated string".into())),
                Some(b'"') => {
                    self.i += 1;
                    return Ok(out);
                }
                Some(b'\\') => {
                    self.i += 1;
                    match self.peek() {
                        Some(b'"') => out.push('"'),
                        Some(b'\\') => out.push('\\'),
                        Some(b'/') => out.push('/'),
                        Some(b'n') => out.push('\n'),
                        Some(b't') => out.push('\t'),
                        Some(b'r') => out.push('\r'),
                        Some(b'b') => out.push('\u{8}'),
                        Some(b'f') => out.push('\u{c}'),
                        Some(b'u') => {
                            if self.i + 4 >= self.b.len() {
                                return Err(Error("bad \\u".into()));
                            }
                            let hex = std::str::from_utf8(&self.b[self.i + 1..self.i + 5])
                                .map_err(|_| Error("bad \\u".into()))?;
                            let cp = u32::from_str_radix(hex, 16).map_err(|_| Error("bad \\u".into()))?;
                            out.push(char::from_u32(cp).ok_or_else(|| Error("bad codepoint".into()))?);
                            self.i += 4;
                        }
                        _ => return Err(Error("bad escape".into())),
                    }
                    self.i += 1;
                }
                Some(c) if c < 0x20 => return Err(Error("control char in string".into())),
                Some(_) => {
                    // consume one UTF-8 code point
                    let rest = std::str::from_utf8(&self.b[self.i..]).map_err(|_| Error("bad utf-8".into()))?;
                    let ch = rest.chars().next().unwrap();
                    out.push(ch);
                    self.i += ch.len_utf8();
                }
            }
        }
    }
    fn number(&mut self) -> Result<Value, Error> {
        let start = self.i;
        if self.peek() == Some(b'-') {
            self.i += 1;
        }
        while self.peek().map(|c| c.is_ascii_digit() || c == b'.' || c == b'e' || c == b'E' || c == b'+' || c == b'-').unwrap_or(false) {
            self.i += 1;
        }
        let txt = std::str::from_utf8(&self.b[start..self.i]).map_err(|_| Error("bad number".into()))?;
        txt.parse::<f64>().map(Value::Number).map_err(|_| Error("bad number".into()))
    }
}

/// Minimal serde_json::Value::Null re-export shape used in matches.
pub use Value as JsonValue;
