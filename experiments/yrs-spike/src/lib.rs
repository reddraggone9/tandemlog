//! Disposable investigation only; not a production protocol or security boundary.
mod admission;
use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde_json::{json, Value};
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use yrs::updates::decoder::Decode;
use yrs::{
    Assoc, ClientID, Doc, GetString, IndexedSequence, OffsetKind, Options, ReadTxn, StateVector,
    StickyIndex, Text, TextRef, Transact, UndoManager, Update,
};

const MAX: usize = 65536;
struct Replica {
    doc: Doc,
    text: TextRef,
    undo: UndoManager,
    baseline: Option<StateVector>,
    source: Option<(String, String)>,
    composing: bool,
    anchor: Option<StickyIndex>,
}
impl Replica {
    fn new(client: u64, seed: Option<&[u8]>) -> Result<Self, String> {
        if client < 2 || client >= (1 << 53) {
            return Err("actor outside prototype range".into());
        }
        let doc = make_doc(client);
        let text = doc.get_or_insert_text("text");
        if let Some(bytes) = seed {
            admission::Admission::parse(bytes)?.check_initial()?;
            doc.transact_mut_with("remote")
                .apply_update(decode(bytes)?)
                .map_err(|e| e.to_string())?;
        }
        if text.get_string(&doc.transact()).encode_utf16().count() > MAX {
            return Err("text size limit".into());
        }
        let mut opts = yrs::undo::Options::default();
        opts.tracked_origins.insert("local".into());
        opts.capture_timeout_millis = 0;
        let mut undo = UndoManager::with_options(opts);
        undo.expand_scope(&doc, &text);
        Ok(Self {
            doc,
            text,
            undo,
            baseline: None,
            source: None,
            composing: false,
            anchor: None,
        })
    }
    fn pending(&self) -> bool {
        let t = self.doc.transact();
        t.store().pending_update().is_some() || t.store().pending_ds().is_some()
    }
    fn string(&self) -> String {
        self.text.get_string(&self.doc.transact())
    }
    fn full(&self) -> Vec<u8> {
        self.doc
            .transact()
            .encode_state_as_update_v1(&StateVector::default())
    }
}
fn make_doc(client: u64) -> Doc {
    let mut o = Options::default();
    o.client_id = ClientID::new(client);
    o.offset_kind = OffsetKind::Utf16;
    // Preserve deleted content so admission can compare immutable actor/clock
    // identity after checkpoint/restart. This has an explicit bounded-history
    // cost; production compaction/admission policy remains unadopted.
    o.skip_gc = true;
    Doc::with_options(o)
}
fn decode(bytes: &[u8]) -> Result<Update, String> {
    if bytes.is_empty() || bytes.len() > MAX {
        return Err("update size limit".into());
    }
    Update::decode_v1(bytes).map_err(|e| format!("invalid engine update: {e}"))
}
fn bytes(v: &Value, key: &str) -> Result<Vec<u8>, String> {
    let s = string(v, key)?;
    if s.len() > ((MAX + 2) / 3) * 4 {
        return Err("encoded update size limit".into());
    }
    STANDARD.decode(s).map_err(|_| "invalid base64".into())
}
fn string<'a>(v: &'a Value, key: &str) -> Result<&'a str, String> {
    v[key]
        .as_str()
        .ok_or_else(|| format!("missing string {key}"))
}
fn number(v: &Value, key: &str) -> Result<u64, String> {
    v[key]
        .as_u64()
        .ok_or_else(|| format!("missing integer {key}"))
}
fn boundary(s: &str, index: u64) -> bool {
    let mut at = 0u64;
    if index == 0 {
        return true;
    }
    for c in s.chars() {
        at += c.len_utf16() as u64;
        if at == index {
            return true;
        }
        if at > index {
            return false;
        }
    }
    false
}
#[derive(Default)]
struct Engine {
    docs: HashMap<String, Replica>,
}
impl Engine {
    fn get(&mut self, name: &str) -> Result<&mut Replica, String> {
        self.docs
            .get_mut(name)
            .ok_or_else(|| "unknown replica".into())
    }
    fn add(&mut self, name: String, r: Replica) -> Result<Value, String> {
        if self.docs.contains_key(&name) {
            return Err("replica exists".into());
        }
        if self
            .docs
            .values()
            .any(|d| d.doc.client_id() == r.doc.client_id())
        {
            return Err("active actor collision".into());
        }
        self.docs.insert(name, r);
        Ok(json!({"ok":true}))
    }
    fn apply_to(&mut self, name: &str, data: &[u8], origin: &str) -> Result<Value, String> {
        // Decode+apply to a scratch clone before mutating the real replica.
        let r = self.get(name)?;
        if r.baseline.is_some() {
            return Err("remote updates cannot enter a private captured draft".into());
        }
        let previous = r.full();
        admission::Admission::parse(data)?
            .check_against(&admission::Admission::parse(&previous)?)?;
        let check = make_doc((1 << 53) - 1);
        let text = check.get_or_insert_text("text");
        check
            .transact_mut()
            .apply_update(decode(&previous)?)
            .map_err(|e| e.to_string())?;
        check
            .transact_mut()
            .apply_update(decode(data)?)
            .map_err(|e| e.to_string())?;
        if text.get_string(&check.transact()).encode_utf16().count() > MAX {
            return Err("text size limit".into());
        }
        r.doc
            .transact_mut_with(origin)
            .apply_update(decode(data)?)
            .map_err(|e| e.to_string())?;
        Ok(json!({"text":r.string(),"pending":r.pending()}))
    }
    fn command(&mut self, v: Value) -> Result<Value, String> {
        let op = string(&v, "op")?;
        match op {
            "reset" => {
                self.docs.clear();
                return Ok(json!({"ok":true}));
            }
            "seed" => {
                let s = string(&v, "text")?;
                if s.encode_utf16().count() > MAX {
                    return Err("text size limit".into());
                }
                let d = make_doc(1);
                let t = d.get_or_insert_text("text");
                t.insert(&mut d.transact_mut(), 0, s);
                return Ok(
                    json!({"update":STANDARD.encode(d.transact().encode_state_as_update_v1(&StateVector::default()))}),
                );
            }
            _ => {}
        }
        let name = string(&v, "name")?.to_owned();
        match op {
            "new" => {
                let seed = if v["seed"].is_string() {
                    Some(bytes(&v, "seed")?)
                } else {
                    None
                };
                let r = Replica::new(number(&v, "client")?, seed.as_deref())?;
                self.add(name, r)
            }
            "draft" => {
                let from = string(&v, "source")?;
                let source = self.get(from)?;
                if source.baseline.is_some() {
                    return Err("nested private draft".into());
                }
                let data = source.full();
                let baseline = source.doc.transact().state_vector();
                let guid = source.doc.guid().to_string();
                let mut r = Replica::new(number(&v, "client")?, Some(&data))?;
                r.baseline = Some(baseline);
                r.source = Some((from.into(), guid));
                self.add(name, r)
            }
            "cancel" => {
                self.docs.remove(&name).ok_or("unknown replica")?;
                Ok(json!({"ok":true}))
            }
            "read" => {
                let r = self.get(&name)?;
                Ok(json!({"text":r.string(),"pending":r.pending()}))
            }
            "state" => {
                let r = self.get(&name)?;
                Ok(json!({"update":STANDARD.encode(r.full())}))
            }
            "diff" => {
                let r = self.get(&name)?;
                Ok(
                    json!({"update":STANDARD.encode(r.doc.transact().encode_diff_v1(&StateVector::default()))}),
                )
            }
            "checkpoint" => {
                let r = self.get(&name)?;
                Ok(
                    json!({"checkpoint":{"schema":1,"codec":"yrs-v1","state":STANDARD.encode(r.full())}}),
                )
            }
            "restore" => {
                let c = &v["checkpoint"];
                if c["schema"] != 1 || c["codec"] != "yrs-v1" {
                    return Err("unknown checkpoint".into());
                }
                let data = bytes(c, "state")?;
                let r = Replica::new(number(&v, "client")?, Some(&data))?;
                self.add(name, r)
            }
            "composition" => {
                let r = self.get(&name)?;
                r.composing = v["active"].as_bool().ok_or("missing active")?;
                Ok(json!({"ok":true}))
            }
            "edit" => {
                let index = number(&v, "index")?;
                let delete = number(&v, "delete")?;
                let insert = string(&v, "insert")?;
                let r = self.get(&name)?;
                let old = r.string();
                let len = old.encode_utf16().count() as u64;
                let end = index.checked_add(delete).ok_or("offset overflow")?;
                if end > len || !boundary(&old, index) || !boundary(&old, end) {
                    return Err("invalid UTF-16 boundary".into());
                }
                if len - delete + insert.encode_utf16().count() as u64 > MAX as u64 {
                    return Err("text size limit".into());
                }
                r.undo.reset();
                let mut tx = r.doc.transact_mut_with("local");
                if delete > 0 {
                    r.text.remove_range(&mut tx, index as u32, delete as u32);
                }
                if !insert.is_empty() {
                    r.text.insert(&mut tx, index as u32, insert);
                }
                let update = tx.encode_update_v1();
                drop(tx);
                Ok(json!({"update":STANDARD.encode(update),"text":r.string()}))
            }
            "apply" => {
                let data = bytes(&v, "update")?;
                self.apply_to(&name, &data, "remote")
            }
            "apply_local" => {
                // Isolated coordinator calls this only after exact durable
                // receipt of a locally prepared packet. It is not an app API.
                let data = bytes(&v, "update")?;
                self.get(&name)?.undo.reset();
                self.apply_to(&name, &data, "local")
            }
            "prepare" => {
                let target = string(&v, "target")?.to_owned();
                let target_guid = self.get(&target)?.doc.guid().to_string();
                let r = self.get(&name)?;
                if r.composing {
                    return Err("composition active".into());
                }
                if r.source.as_ref() != Some(&(target, target_guid)) {
                    return Err("draft source identity changed or wrong target".into());
                }
                let baseline = r.baseline.as_ref().ok_or("not a captured draft")?;
                let data = r.doc.transact().encode_diff_v1(baseline);
                Ok(json!({"update":STANDARD.encode(data)}))
            }
            "save" => {
                let target = string(&v, "target")?.to_owned();
                let target_guid = self.get(&target)?.doc.guid().to_string();
                let r = self.get(&name)?;
                if r.composing {
                    return Err("composition active".into());
                }
                if r.source.as_ref() != Some(&(target.clone(), target_guid)) {
                    return Err("draft source identity changed or wrong target".into());
                }
                let baseline = r.baseline.as_ref().ok_or("not a captured draft")?;
                let data = r.doc.transact().encode_diff_v1(baseline);
                self.get(&target)?.undo.reset();
                self.apply_to(&target, &data, "local")?;
                self.docs.remove(&name);
                Ok(json!({"update":STANDARD.encode(data),"text":self.get(&target)?.string()}))
            }
            "undo" | "redo" => {
                let r = self.get(&name)?;
                let before = r.doc.transact().state_vector();
                let changed = if op == "undo" {
                    r.undo.undo_blocking()
                } else {
                    r.undo.redo_blocking()
                };
                let update = r.doc.transact().encode_diff_v1(&before);
                Ok(json!({"changed":changed,"update":STANDARD.encode(update),"text":r.string()}))
            }
            "anchor" => {
                let index = number(&v, "index")?;
                let r = self.get(&name)?;
                if !boundary(&r.string(), index) {
                    return Err("invalid anchor boundary".into());
                }
                r.anchor =
                    r.text
                        .sticky_index(&mut r.doc.transact_mut(), index as u32, Assoc::After);
                Ok(json!({"ok":true}))
            }
            "anchor_read" => {
                let r = self.get(&name)?;
                let offset = r
                    .anchor
                    .as_ref()
                    .ok_or("no anchor")?
                    .get_offset(&r.doc.transact())
                    .ok_or("anchor invalid")?;
                Ok(json!({"index":offset.index}))
            }
            _ => Err("unknown prototype command".into()),
        }
    }
}
thread_local! {static ENGINE:RefCell<Engine>=RefCell::new(Engine::default());}
/// Only trusted caller-owned NUL-terminated UTF-8 pointers are accepted by the ABI.
/// Native parser isolation / arbitrary pointer defense is NOT claimed.
#[no_mangle]
pub unsafe extern "C" fn spike_json(input: *const c_char) -> *mut c_char {
    let out = std::panic::catch_unwind(|| {
        if input.is_null() {
            return Err("null input".into());
        }
        let raw = CStr::from_ptr(input).to_bytes();
        if raw.len() > 300000 {
            return Err("request size limit".into());
        }
        let v: Value = serde_json::from_slice(raw).map_err(|_| "invalid JSON".to_owned())?;
        ENGINE.with(|e| e.borrow_mut().command(v))
    });
    let value = match out {
        Ok(Ok(v)) => v,
        Ok(Err(e)) => json!({"error":e}),
        Err(_) => json!({"error":"caught engine panic; prototype not adopted"}),
    };
    CString::new(value.to_string()).unwrap().into_raw()
}
#[no_mangle]
pub unsafe extern "C" fn spike_free(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}
#[no_mangle]
pub unsafe extern "C" fn spike_alloc(size: usize) -> *mut u8 {
    if size == 0 || size > 300001 {
        return std::ptr::null_mut();
    }
    std::alloc::alloc_zeroed(std::alloc::Layout::array::<u8>(size).unwrap())
}
#[no_mangle]
pub unsafe extern "C" fn spike_release_input(value: *mut u8, size: usize) {
    if !value.is_null() && size > 0 && size <= 300001 {
        std::alloc::dealloc(value, std::alloc::Layout::array::<u8>(size).unwrap());
    }
}
