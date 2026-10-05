// Owned plain-text native engine. Canonical source; application adoption gates remain open.
mod admission;
use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::sync::mpsc::{self, Sender};
use std::sync::{Arc, Mutex, OnceLock};
use yrs::undo::UndoManager;
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use yrs::{
    Assoc, ClientID, Doc, GetString, IndexedSequence, OffsetKind, Options, ReadTxn, StateVector,
    StickyIndex, Text, TextRef, Transact, Update,
};

const MAX: usize = 65536;
const STATE_CAP: usize = 8 * 1024 * 1024;
const SESSION_CAP: usize = 16 * 1024 * 1024;
const RETAINED_CAP: usize = 64 * 1024 * 1024;
const OPERATION_CAP: usize = 1024 * 1024;
const REQUEST_CAP: usize = 12 * 1024 * 1024;
const RESPONSE_CAP: usize = 24 * 1024 * 1024;

#[derive(Clone)]
struct Limits {
    units: Option<usize>,
    visible: usize,
    update: usize,
    state: usize,
    session: usize,
    retained: usize,
}
impl Default for Limits {
    fn default() -> Self {
        Self {
            units: None,
            visible: MAX,
            update: MAX,
            state: STATE_CAP,
            session: SESSION_CAP,
            retained: RETAINED_CAP,
        }
    }
}
impl Limits {
    fn parse(value: &Value) -> Result<Self, String> {
        if value.is_null() {
            return Ok(Self::default());
        }
        let fields = value.as_object().ok_or("invalid limits")?;
        if fields.keys().any(|key| {
            ![
                "admissionUnits",
                "visibleUtf16",
                "updateBytes",
                "stateBytes",
                "sessionBytes",
                "retainedBytes",
            ]
            .contains(&key.as_str())
        }) {
            return Err("unknown limit".into());
        }
        let mut result = Self::default();
        for (key, target, cap) in [
            ("visibleUtf16", &mut result.visible, STATE_CAP),
            ("updateBytes", &mut result.update, OPERATION_CAP),
            ("stateBytes", &mut result.state, STATE_CAP),
            ("sessionBytes", &mut result.session, SESSION_CAP),
            ("retainedBytes", &mut result.retained, RETAINED_CAP),
        ] {
            if let Some(value) = fields.get(key) {
                let size = value.as_u64().ok_or("limit must be a positive integer")?;
                if size == 0 || size > cap as u64 {
                    return Err("limit outside supported budget".into());
                }
                *target = size as usize;
            }
        }
        if let Some(value) = fields.get("admissionUnits") {
            result.units = Some(unit_limit(value)?);
        }
        Ok(result)
    }
    fn units(&self) -> usize {
        self.units.unwrap_or(STATE_CAP)
    }
    fn json(&self) -> Value {
        let mut result = json!({"visibleUtf16":self.visible,"updateBytes":self.update,"stateBytes":self.state,"sessionBytes":self.session,"retainedBytes":self.retained});
        if let Some(units) = self.units {
            result["admissionUnits"] = json!(units);
        }
        result
    }
}
#[derive(Default)]
struct Usage {
    state: usize,
    replay: usize,
    prepared: usize,
    receipt: usize,
    retained: usize,
    session: usize,
}

#[derive(Clone)]
enum ReplayStep {
    Apply(Vec<u8>, String),
    Owned(Vec<u8>, String),
    Undo,
    UndoOperation(String),
    Redo,
}
struct PreparedUndo {
    token: String,
    operation: Option<String>,
    update: Vec<u8>,
    replica: Box<Replica>,
    remote: Vec<Vec<u8>>,
}
#[derive(Clone)]
struct UndoReceipt {
    name: String,
    guid: yrs::Uuid,
    update: Vec<u8>,
    response: Value,
}
struct Replica {
    doc: Doc,
    text: TextRef,
    undo: UndoManager<String>,
    baseline: Option<StateVector>,
    source: Option<(String, String)>,
    composing: bool,
    anchor: Option<StickyIndex>,
    // Session-only ownership replay, not a replacement for the canonical journal.
    initial_seed: Option<Vec<u8>>,
    replay: Vec<ReplayStep>,
    prepared_undo: Option<PreparedUndo>,
    limits: Limits,
}
impl Replica {
    fn new_with_limits(client: u64, seed: Option<&[u8]>, limits: Limits) -> Result<Self, String> {
        Self::new_with_guid(client, seed, None, limits)
    }
    fn new_with_guid(
        client: u64,
        seed: Option<&[u8]>,
        guid: Option<yrs::Uuid>,
        limits: Limits,
    ) -> Result<Self, String> {
        if client < 2 || client >= (1 << 53) {
            return Err("actor outside prototype range".into());
        }
        let doc = make_doc_with_guid(client, guid);
        let text = doc.get_or_insert_text("text");
        if let Some(bytes) = seed {
            admission::Admission::parse_with_budgets(bytes, limits.state, limits.units())?
                .check_initial()?;
            doc.transact_mut_with("remote")
                .apply_update(decode_limit(bytes, limits.state)?)
                .map_err(|e| e.to_string())?;
        }
        if text.get_string(&doc.transact()).encode_utf16().count() > limits.visible {
            return Err("text size limit".into());
        }
        let mut opts = yrs::undo::Options::<String>::default();
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
            initial_seed: seed.map(|bytes| bytes.to_vec()),
            replay: Vec::new(),
            prepared_undo: None,
            limits,
        })
    }
    fn snapshot(&self) -> Result<Self, String> {
        let mut result = self.recreate()?;
        if let Some(p) = &self.prepared_undo {
            result.prepared_undo = Some(PreparedUndo {
                token: p.token.clone(),
                operation: p.operation.clone(),
                update: p.update.clone(),
                replica: Box::new(p.replica.snapshot()?),
                remote: p.remote.clone(),
            });
        }
        Ok(result)
    }
    fn usage(&self, receipt: usize, owner_name: usize) -> Usage {
        let state = self.full().len();
        let replay = self.initial_seed.as_ref().map_or(0, Vec::len)
            + self
                .replay
                .iter()
                .map(|step| match step {
                    ReplayStep::Apply(data, origin) => 1 + data.len() + origin.len(),
                    ReplayStep::Owned(data, operation) => 1 + data.len() + operation.len(),
                    ReplayStep::UndoOperation(operation) => 1 + operation.len(),
                    _ => 1,
                })
                .sum::<usize>();
        let metadata = owner_name
            + self.doc.guid().len()
            + 8
            + 1
            + self
                .source
                .as_ref()
                .map_or(0, |(name, guid)| name.len() + guid.len())
            + self
                .baseline
                .as_ref()
                .map_or(0, |vector| vector.encode_v1().len())
            + self
                .anchor
                .as_ref()
                .map_or(0, |anchor| anchor.encode_v1().len());
        let mut session = replay;
        let prepared = self.prepared_undo.as_ref().map_or(0, |p| {
            let nested = p.replica.usage(0, 0);
            let queued = p.remote.iter().map(|data| data.len() + 1).sum::<usize>();
            let operation = p.operation.as_ref().map_or(0, String::len);
            session += p.token.len() + operation + p.update.len() + nested.session + queued;
            p.token.len() + operation + p.update.len() + nested.retained + queued
        });
        Usage {
            state,
            replay,
            prepared,
            receipt,
            retained: state + replay + metadata + prepared + receipt,
            session,
        }
    }
    fn check_budget(&self, receipt: usize, owner_name: usize) -> Result<(), String> {
        admission::Admission::parse_with_budgets(
            &self.full(),
            self.limits.state,
            self.limits.units(),
        )?;
        let usage = self.usage(receipt, owner_name);
        if self.string().encode_utf16().count() > self.limits.visible {
            return Err("visible text budget exceeded".into());
        }
        if usage.state > self.limits.state {
            return Err("encoded state budget exceeded".into());
        }
        if usage.session > self.limits.session {
            return Err("session replay budget exceeded".into());
        }
        if usage.retained > self.limits.retained {
            return Err("retained serialized payload budget exceeded".into());
        }
        if let Some(p) = &self.prepared_undo {
            p.replica.check_budget(0, 0)?;
        }
        Ok(())
    }
    fn require_local_ready(&self) -> Result<(), String> {
        if self.prepared_undo.is_some() {
            return Err("prepared Undo awaits receipt or cancellation".into());
        }
        Ok(())
    }
    fn recreate(&self) -> Result<Self, String> {
        let mut clone = Self::new_with_guid(
            self.doc.client_id().get(),
            self.initial_seed.as_deref(),
            Some(self.doc.guid()),
            self.limits.clone(),
        )?;
        for step in &self.replay {
            match step {
                ReplayStep::Apply(update, origin) => {
                    if origin == "local" {
                        clone.undo.reset();
                    }
                    clone
                        .doc
                        .transact_mut_with(origin.as_str())
                        .apply_update(decode_limit(update, self.limits.update)?)
                        .map_err(|e| e.to_string())?;
                }
                ReplayStep::Undo => {
                    clone.undo.undo_blocking();
                }
                ReplayStep::Owned(update, operation) => {
                    clone.apply_owned(update, operation)?;
                }
                ReplayStep::UndoOperation(operation) => {
                    clone.undo_operation(operation)?;
                }
                ReplayStep::Redo => {
                    clone.undo.redo_blocking();
                }
            }
        }
        if clone.full() != self.full() {
            return Err("session Undo replay differs from live state".into());
        }
        clone.replay = self.replay.clone();
        clone.source = self.source.clone();
        clone.baseline = self.baseline.clone();
        clone.composing = self.composing;
        clone.anchor = self.anchor.clone();
        Ok(clone)
    }
    fn apply_owned(&mut self, data: &[u8], operation: &str) -> Result<(), String> {
        if operation.is_empty() || operation.len() > 128 {
            return Err("invalid owned operation identity".into());
        }
        if let Some(existing) = self.replay.iter().find_map(|step| match step {
            ReplayStep::Owned(update, id) if id == operation => Some(update),
            _ => None,
        }) {
            return if existing == data {
                Ok(())
            } else {
                Err("owned operation identity reused with different bytes".into())
            };
        }
        let id = operation.to_owned();
        self.undo
            .observe_item_added("owned-operation", move |_, event| {
                *event.meta_mut() = id.clone();
            });
        let result = self.apply_recorded(data, "local");
        self.undo.unobserve_item_added("owned-operation");
        result?;
        self.replay.pop();
        self.replay
            .push(ReplayStep::Owned(data.to_vec(), operation.into()));
        Ok(())
    }
    fn install_undo_stacks(
        &mut self,
        undo: Vec<yrs::undo::StackItem<String>>,
        redo: Vec<yrs::undo::StackItem<String>>,
    ) {
        let mut options = yrs::undo::Options::<String>::default();
        options.tracked_origins.insert("local".into());
        options.capture_timeout_millis = 0;
        options.init_undo_stack = undo;
        options.init_redo_stack = redo;
        // Drop unregisters the old observers. Documents disable GC, so changing
        // the manager does not discard the retained identity/redone graph.
        self.undo = UndoManager::with_options(options);
        self.undo.expand_scope(&self.doc, &self.text);
    }
    fn undo_operation(&mut self, operation: &str) -> Result<bool, String> {
        let mut remaining = self.undo.undo_stack().to_vec();
        let selected = remaining
            .iter()
            .position(|item| item.meta() == operation)
            .ok_or("owned operation has no retained Undo item")?;
        let item = remaining.remove(selected);
        let redo = self.undo.redo_stack().to_vec();
        self.install_undo_stacks(vec![item], redo);
        let id = operation.to_owned();
        self.undo
            .observe_item_added("owned-operation", move |_, event| {
                *event.meta_mut() = id.clone();
            });
        // Yrs may skip ineffective items. It sees only the named item here,
        // so an ineffective latest Save cannot consume any earlier Save.
        let changed = self.undo.undo_blocking();
        self.undo.unobserve_item_added("owned-operation");
        let redo = self.undo.redo_stack().to_vec();
        self.install_undo_stacks(remaining, redo);
        Ok(changed)
    }
    fn apply_recorded(&mut self, data: &[u8], origin: &str) -> Result<(), String> {
        let previous = self.full();
        admission::Admission::parse_with_budgets(data, self.limits.update, self.limits.units())?
            .check_combined(
                &admission::Admission::parse_with_budgets(
                    &previous,
                    self.limits.state,
                    self.limits.units(),
                )?,
                self.limits.units(),
            )?;
        let check = make_doc((1 << 53) - 1);
        let text = check.get_or_insert_text("text");
        check
            .transact_mut()
            .apply_update(decode_limit(&previous, self.limits.state)?)
            .map_err(|e| e.to_string())?;
        check
            .transact_mut()
            .apply_update(decode_limit(data, self.limits.update)?)
            .map_err(|e| e.to_string())?;
        if text.get_string(&check.transact()).encode_utf16().count() > self.limits.visible {
            return Err("text size limit".into());
        }
        if origin == "local" {
            self.undo.reset();
        }
        self.doc
            .transact_mut_with(origin)
            .apply_update(decode_limit(data, self.limits.update)?)
            .map_err(|e| e.to_string())?;
        self.replay
            .push(ReplayStep::Apply(data.to_vec(), origin.into()));
        Ok(())
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
    make_doc_with_guid(client, None)
}
fn make_doc_with_guid(client: u64, guid: Option<yrs::Uuid>) -> Doc {
    let mut o = Options::default();
    o.client_id = ClientID::new(client);
    if let Some(guid) = guid {
        o.guid = guid;
    }
    o.offset_kind = OffsetKind::Utf16;
    // Preserve deleted content so admission can compare immutable actor/clock
    // identity after checkpoint/restart. This has an explicit bounded-history
    // cost; production compaction/admission policy remains unadopted.
    o.skip_gc = true;
    Doc::with_options(o)
}
fn unit_limit(value: &Value) -> Result<usize, String> {
    let n = value
        .as_u64()
        .ok_or("admission limit must be positive integer")?;
    if n == 0 || n > STATE_CAP as u64 {
        return Err("admission limit outside supported budget".into());
    }
    Ok(n as usize)
}
fn decode_limit(bytes: &[u8], limit: usize) -> Result<Update, String> {
    if bytes.is_empty() || bytes.len() > limit {
        return Err("update byte budget exceeded".into());
    }
    Update::decode_v1(bytes).map_err(|e| format!("invalid engine update: {e}"))
}
fn bytes_limit(v: &Value, key: &str, limit: usize) -> Result<Vec<u8>, String> {
    let s = string(v, key)?;
    if s.len() > ((limit + 2) / 3) * 4 {
        return Err("encoded update size limit".into());
    }
    let decoded = STANDARD
        .decode(s)
        .map_err(|_| "invalid base64".to_owned())?;
    if decoded.is_empty() || decoded.len() > limit {
        return Err("decoded update byte budget exceeded".into());
    }
    Ok(decoded)
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
    next_preparation: u64,
    undo_receipts: HashMap<String, UndoReceipt>,
}
impl Engine {
    fn receipt_weight(receipt: &UndoReceipt, token: &str) -> usize {
        token.len()
            + receipt.name.len()
            + receipt.guid.len()
            + receipt.update.len()
            + receipt.response.to_string().len()
    }
    fn owner_receipts(&self, name: &str) -> usize {
        self.undo_receipts
            .iter()
            .filter(|(_, r)| r.name == name)
            .map(|(token, r)| Self::receipt_weight(r, token))
            .sum()
    }
    fn retained_weight(&self) -> usize {
        self.docs
            .iter()
            .map(|(name, r)| r.usage(0, name.len()).retained)
            .sum::<usize>()
            + self
                .undo_receipts
                .iter()
                .map(|(token, r)| Self::receipt_weight(r, token))
                .sum::<usize>()
    }
    fn command(&mut self, v: Value) -> Result<Value, String> {
        let op = string(&v, "op")?;
        // Explicit owner mutations reuse the existing private replay mechanism;
        // reject any operation budget before replacing live state/Undo/drafts.
        if ![
            "edit",
            "apply",
            "apply_local",
            "apply_owned",
            "save",
            "undo",
            "redo",
            "prepare_undo",
            "prepare_operation_undo",
            "commit_undo",
            "cancel_prepared_undo",
            "composition",
            "anchor",
        ]
        .contains(&op)
        {
            let response = self.command_inner(v)?;
            if response.to_string().len() > RESPONSE_CAP {
                return Err("response frame budget exceeded".into());
            }
            return Ok(response);
        }
        let reserve_undo_marker = !["undo", "redo", "commit_undo"].contains(&op);
        let name = string(&v, "name")?.to_owned();
        let mut names = vec![name];
        if op == "save" {
            let target = string(&v, "target")?.to_owned();
            if !names.contains(&target) {
                names.push(target);
            }
        }
        let mut candidate = Engine {
            docs: HashMap::new(),
            next_preparation: self.next_preparation,
            undo_receipts: self
                .undo_receipts
                .iter()
                .filter(|(_, r)| names.contains(&r.name))
                .map(|(token, r)| (token.clone(), r.clone()))
                .collect(),
        };
        for name in &names {
            candidate
                .docs
                .insert(name.clone(), self.get(name)?.snapshot()?);
        }
        let response = candidate.command_inner(v)?;
        if response.to_string().len() > RESPONSE_CAP {
            return Err("response frame budget exceeded".into());
        }
        for (name, r) in &candidate.docs {
            r.check_budget(candidate.owner_receipts(name), name.len())?;
            // Keep one compact replay marker available for the prior session
            // Undo; rejecting a new edit must not consume or prune that history.
            if reserve_undo_marker
                && r.undo.can_undo()
                && r.usage(0, name.len()).session.saturating_add(
                    1 + r
                        .undo
                        .undo_stack()
                        .last()
                        .map_or(0, |item| item.meta().len()),
                ) > r.limits.session
            {
                return Err("session replay budget needs Undo marker headroom".into());
            }
        }
        let untouched = self
            .docs
            .iter()
            .filter(|(name, _)| !names.contains(name))
            .map(|(name, r)| r.usage(0, name.len()).retained)
            .sum::<usize>()
            + self
                .undo_receipts
                .iter()
                .filter(|(_, r)| !names.contains(&r.name))
                .map(|(token, r)| Self::receipt_weight(r, token))
                .sum::<usize>();
        if untouched.saturating_add(candidate.retained_weight()) > RETAINED_CAP {
            return Err("global serialized payload budget exceeded".into());
        }
        for name in names {
            self.docs.remove(&name);
            self.undo_receipts.retain(|_, r| r.name != name);
        }
        self.docs.extend(candidate.docs);
        self.undo_receipts.extend(candidate.undo_receipts);
        self.next_preparation = candidate.next_preparation;
        Ok(response)
    }
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
        r.check_budget(0, name.len())?;
        if self
            .retained_weight()
            .saturating_add(r.usage(0, name.len()).retained)
            > RETAINED_CAP
        {
            return Err("global serialized payload budget exceeded".into());
        }
        let response =
            json!({"ok":true,"guid":r.doc.guid().to_string(),"client":r.doc.client_id().get()});
        self.docs.insert(name, r);
        Ok(response)
    }
    fn apply_to(&mut self, name: &str, data: &[u8], origin: &str) -> Result<Value, String> {
        // Decode+apply to a scratch clone before mutating the real replica.
        let r = self.get(name)?;
        if r.baseline.is_some() {
            return Err("remote updates cannot enter a private captured draft".into());
        }
        if origin == "local" {
            r.require_local_ready()?;
        }
        r.apply_recorded(data, origin)?;
        if origin == "remote" {
            if let Some(prepared) = r.prepared_undo.as_mut() {
                prepared.remote.push(data.to_vec());
            }
        }
        Ok(json!({"text":r.string(),"pending":r.pending()}))
    }
    fn prepare_undo(&mut self, name: &str, operation: Option<&str>) -> Result<Value, String> {
        let r = self.get(name)?;
        if r.baseline.is_some() {
            return Err("private draft Undo is not a durable preparation".into());
        }
        if let Some(p) = &r.prepared_undo {
            if p.operation.as_deref() != operation {
                return Err("prepared Undo belongs to another operation".into());
            }
            return Ok(json!({"changed":true,"token":p.token,"update":STANDARD.encode(&p.update)}));
        }
        if !r.undo.can_undo() {
            return Err("no session Undo available".into());
        }
        let mut candidate = r.recreate()?;
        // Capture the actual compensation transaction, not a whole-field
        // replacement or a state-vector diff containing all historical deletes.
        let captured = Arc::new(Mutex::new(Vec::<Vec<u8>>::new()));
        let copy = captured.clone();
        candidate
            .doc
            .observe_update_v1("prepared-compensation", move |_, event| {
                copy.lock().unwrap().push(event.update.clone());
            })
            .map_err(|e| e.to_string())?;
        let changed = match operation {
            Some(id) => candidate.undo_operation(id)?,
            None => candidate.undo.undo_blocking(),
        };
        candidate
            .doc
            .unobserve_update_v1("prepared-compensation")
            .map_err(|e| e.to_string())?;
        if !changed && operation.is_none() {
            return Err("no effective session Undo available".into());
        }
        let packets = captured.lock().unwrap();
        let update =
            yrs::merge_updates_v1(packets.iter().map(Vec::as_slice)).map_err(|e| e.to_string())?;
        drop(packets);
        decode_limit(&update, candidate.limits.update)?;
        candidate.replay.push(match operation {
            Some(id) => ReplayStep::UndoOperation(id.to_owned()),
            None => ReplayStep::Undo,
        });
        let guid = r.doc.guid();
        self.next_preparation = self
            .next_preparation
            .checked_add(1)
            .ok_or("preparation identity exhausted")?;
        let token = format!("{}:{}", guid, self.next_preparation);
        let response = json!({"changed":true,"token":token,"update":STANDARD.encode(&update)});
        self.get(name)?.prepared_undo = Some(PreparedUndo {
            token,
            operation: operation.map(str::to_owned),
            update,
            replica: Box::new(candidate),
            remote: Vec::new(),
        });
        Ok(response)
    }
    fn commit_undo(&mut self, name: &str, token: &str, receipt: &[u8]) -> Result<Value, String> {
        let guid = self.get(name)?.doc.guid();
        if let Some(done) = self.undo_receipts.get(token) {
            if done.name != name || done.guid != guid || done.update != receipt {
                return Err("prepared Undo receipt owner or bytes mismatch".into());
            }
            return Ok(done.response.clone());
        }
        let r = self.get(name)?;
        let pending = r.prepared_undo.as_ref().ok_or("no prepared Undo")?;
        if pending.token != token || pending.update != receipt {
            return Err("prepared Undo receipt token or bytes mismatch".into());
        }
        // Rebuild a private commit candidate, so failure cannot consume either
        // the original Undo stack or the immutable prepared candidate.
        let mut candidate = pending.replica.recreate()?;
        for remote in &pending.remote {
            candidate.apply_recorded(remote, "remote")?;
        }
        candidate.anchor = r.anchor.clone();
        candidate.composing = r.composing;
        let response = json!({"changed":true,"token":token,"update":STANDARD.encode(receipt),"text":candidate.string(),"pending":candidate.pending()});
        self.docs.insert(name.into(), candidate);
        self.undo_receipts.insert(
            token.into(),
            UndoReceipt {
                name: name.into(),
                guid,
                update: receipt.to_vec(),
                response: response.clone(),
            },
        );
        Ok(response)
    }
    fn command_inner(&mut self, v: Value) -> Result<Value, String> {
        let op = string(&v, "op")?;
        match op {
            "reset" => {
                self.docs.clear();
                self.undo_receipts.clear();
                return Ok(json!({"ok":true}));
            }
            "inspect" => {
                let data = bytes_limit(&v, "update", OPERATION_CAP)?;
                let units = v
                    .get("admissionUnits")
                    .map(unit_limit)
                    .transpose()?
                    .unwrap_or(100000);
                let packet = admission::Admission::parse_with_budgets(&data, OPERATION_CAP, units)?;
                decode_limit(&data, OPERATION_CAP)?;
                return Ok(json!({"structActors":packet.struct_actors()}));
            }
            "seed" => {
                let limits = Limits::parse(&v["limits"])?;
                let s = string(&v, "text")?;
                if s.encode_utf16().count() > limits.visible {
                    return Err("text size limit".into());
                }
                let d = make_doc(1);
                let t = d.get_or_insert_text("text");
                t.insert(&mut d.transact_mut(), 0, s);
                let state = d
                    .transact()
                    .encode_state_as_update_v1(&StateVector::default());
                decode_limit(&state, limits.state)?;
                return Ok(json!({"update":STANDARD.encode(state)}));
            }
            _ => {}
        }
        let name = string(&v, "name")?.to_owned();
        match op {
            "new" => {
                let limits = Limits::parse(&v["limits"])?;
                let seed = if v["seed"].is_string() {
                    Some(bytes_limit(&v, "seed", limits.state)?)
                } else {
                    None
                };
                let r = Replica::new_with_limits(number(&v, "client")?, seed.as_deref(), limits)?;
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
                let mut r = Replica::new_with_limits(
                    number(&v, "client")?,
                    Some(&data),
                    source.limits.clone(),
                )?;
                r.baseline = Some(baseline);
                r.source = Some((from.into(), guid));
                self.add(name, r)
            }
            "cancel" => {
                self.docs.remove(&name).ok_or("unknown replica")?;
                self.undo_receipts.retain(|_, r| r.name != name);
                Ok(json!({"ok":true}))
            }
            "read" => {
                let r = self.get(&name)?;
                Ok(
                    json!({"text":r.string(),"pending":r.pending(),"guid":r.doc.guid().to_string(),"client":r.doc.client_id().get()}),
                )
            }
            "usage" => {
                let receipts = self.owner_receipts(&name);
                let global = self.retained_weight();
                let r = self.get(&name)?;
                let usage = r.usage(receipts, name.len());
                Ok(
                    json!({"ownerGuid":r.doc.guid().to_string(),"client":r.doc.client_id().get(),"visibleUtf16":r.string().encode_utf16().count(),"stateBytes":usage.state,"replayBytes":usage.replay,"preparedBytes":usage.prepared,"receiptBytes":usage.receipt,"retainedBytes":usage.retained,"sessionBytes":usage.session,"globalRetainedBytes":global,"globalLimitBytes":RETAINED_CAP,"limits":r.limits.json(),"accounting":"serialized-payload-bytes-not-native-rss"}),
                )
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
                let limits = Limits::parse(&v["limits"])?;
                let data = bytes_limit(c, "state", limits.state)?;
                let r = Replica::new_with_limits(number(&v, "client")?, Some(&data), limits)?;
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
                r.require_local_ready()?;
                let old = r.string();
                let len = old.encode_utf16().count() as u64;
                let end = index.checked_add(delete).ok_or("offset overflow")?;
                if end > len || !boundary(&old, index) || !boundary(&old, end) {
                    return Err("invalid UTF-16 boundary".into());
                }
                if len - delete + insert.encode_utf16().count() as u64 > r.limits.visible as u64 {
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
                decode_limit(&update, r.limits.update)?;
                r.replay
                    .push(ReplayStep::Apply(update.clone(), "local".into()));
                Ok(json!({"update":STANDARD.encode(update),"text":r.string()}))
            }
            "apply" => {
                let limit = self.get(&name)?.limits.update;
                let data = bytes_limit(&v, "update", limit)?;
                self.apply_to(&name, &data, "remote")
            }
            "apply_local" => {
                // Isolated coordinator calls this only after exact durable
                // receipt of a locally prepared packet. It is not an app API.
                let limit = self.get(&name)?.limits.update;
                let data = bytes_limit(&v, "update", limit)?;
                self.apply_to(&name, &data, "local")
            }
            "apply_owned" => {
                let limit = self.get(&name)?.limits.update;
                let data = bytes_limit(&v, "update", limit)?;
                let operation = string(&v, "operation")?;
                let replica = self.get(&name)?;
                replica.require_local_ready()?;
                if replica.baseline.is_some() {
                    return Err("owned receipts cannot enter a private captured draft".into());
                }
                replica.apply_owned(&data, operation)?;
                Ok(json!({"text":replica.string(),"pending":replica.pending()}))
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
                decode_limit(&data, r.limits.update)?;
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
                self.apply_to(&target, &data, "local")?;
                self.docs.remove(&name);
                Ok(json!({"update":STANDARD.encode(data),"text":self.get(&target)?.string()}))
            }
            "prepare_undo" => self.prepare_undo(&name, None),
            "prepare_operation_undo" => {
                let operation = string(&v, "operation")?;
                self.prepare_undo(&name, Some(operation))
            }
            "commit_undo" => {
                let token = string(&v, "token")?;
                let limit = self.get(&name)?.limits.update;
                let receipt = bytes_limit(&v["receipt"], "update", limit)?;
                self.commit_undo(&name, token, &receipt)
            }
            "cancel_prepared_undo" => {
                let token = string(&v, "token")?;
                let r = self.get(&name)?;
                if r.prepared_undo.as_ref().map(|p| p.token.as_str()) != Some(token) {
                    return Err("unknown prepared Undo token".into());
                }
                r.prepared_undo = None;
                Ok(json!({"ok":true}))
            }
            "undo" | "redo" => {
                let r = self.get(&name)?;
                r.require_local_ready()?;
                let before = r.doc.transact().state_vector();
                let changed = if op == "undo" {
                    r.undo.undo_blocking()
                } else {
                    r.undo.redo_blocking()
                };
                let update = r.doc.transact().encode_diff_v1(&before);
                decode_limit(&update, r.limits.update)?;
                if changed {
                    r.replay.push(if op == "undo" {
                        ReplayStep::Undo
                    } else {
                        ReplayStep::Redo
                    });
                }
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
// Only owned bytes and reply strings cross the worker boundary. Engine and all
// Yrs values are constructed, used and dropped on the worker itself; no unsafe
// Send implementation or caller-thread-local replica registry is involved.
struct OwnedRequest {
    raw: Vec<u8>,
    reply: Sender<String>,
}
static WORKER: OnceLock<Result<Sender<OwnedRequest>, String>> = OnceLock::new();

fn guard_command<F>(quarantined: &mut bool, command: F) -> Value
where
    F: FnOnce() -> Result<Value, String>,
{
    if *quarantined {
        return json!({"error":"native worker quarantined until process restart; outcome unknown"});
    }
    match std::panic::catch_unwind(std::panic::AssertUnwindSafe(command)) {
        Ok(Ok(value)) => value,
        Ok(Err(error)) => json!({"error":error}),
        Err(_) => {
            // A panicking engine may already have mutated. Keep it inaccessible;
            // never silently reset/reseed, retry the command, or claim cancellation.
            *quarantined = true;
            json!({"error":"native worker panicked; quarantined until process restart; outcome unknown"})
        }
    }
}

fn worker_sender() -> Result<&'static Sender<OwnedRequest>, String> {
    WORKER
        .get_or_init(|| {
            let (sender, receiver) = mpsc::channel::<OwnedRequest>();
            std::thread::Builder::new()
                .name("tandemlog-text-owner".into())
                .spawn(move || {
                    let mut engine = Engine::default();
                    let mut quarantined = false;
                    for request in receiver {
                        let value = guard_command(&mut quarantined, || {
                            let value: Value = serde_json::from_slice(&request.raw)
                                .map_err(|_| "invalid JSON".to_owned())?;
                            engine.command(value)
                        });
                        // If the caller abandons the reply, the command may still have
                        // executed. That is an unknown outcome, not an implicit Cancel.
                        let _ = request.reply.send(value.to_string());
                    }
                })
                .map_err(|e| format!("native worker unavailable; outcome unknown: {e}"))?;
            Ok(sender)
        })
        .as_ref()
        .map_err(Clone::clone)
}

fn request_worker(sender: &Sender<OwnedRequest>, raw: Vec<u8>) -> Value {
    let (reply, received) = mpsc::channel();
    if sender.send(OwnedRequest { raw, reply }).is_err() {
        return json!({"error":"native worker unavailable; outcome unknown"});
    }
    match received.recv() {
        Ok(value) => serde_json::from_str(&value)
            .unwrap_or_else(|_| json!({"error":"invalid native worker reply; outcome unknown"})),
        Err(_) => json!({"error":"native worker unavailable; outcome unknown"}),
    }
}

/// Only trusted caller-owned NUL-terminated UTF-8 pointers are accepted by the
/// ABI. Copy input before queueing; outputs have explicit caller-owned allocation
/// lifetime and can be freed from another caller thread. Arbitrary-pointer defense
/// is not claimed. Calls are synchronous, with no native timeout/auto-cancellation.
unsafe fn json_request(input: *const c_char) -> *mut c_char {
    let out = std::panic::catch_unwind(|| {
        if input.is_null() {
            return Err("null input".to_owned());
        }
        let raw = CStr::from_ptr(input).to_bytes();
        if raw.len() > REQUEST_CAP {
            return Err("request size limit".to_owned());
        }
        Ok(request_worker(worker_sender()?, raw.to_vec()))
    });
    let value = match out {
        Ok(Ok(value)) => value,
        Ok(Err(error)) => json!({"error":error}),
        Err(_) => json!({"error":"native ABI panic; outcome unknown"}),
    };
    CString::new(value.to_string()).unwrap().into_raw()
}
unsafe fn free_response(value: *mut c_char) {
    if !value.is_null() {
        drop(CString::from_raw(value));
    }
}
unsafe fn allocate_input(size: usize) -> *mut u8 {
    if size == 0 || size > REQUEST_CAP + 1 {
        return std::ptr::null_mut();
    }
    std::alloc::alloc_zeroed(std::alloc::Layout::array::<u8>(size).unwrap())
}
unsafe fn release_input(value: *mut u8, size: usize) {
    if !value.is_null() && size > 0 && size <= REQUEST_CAP + 1 {
        std::alloc::dealloc(value, std::alloc::Layout::array::<u8>(size).unwrap());
    }
}

#[no_mangle]
pub unsafe extern "C" fn tandemlog_text_json(input: *const c_char) -> *mut c_char {
    json_request(input)
}
#[no_mangle]
pub unsafe extern "C" fn tandemlog_text_free(value: *mut c_char) {
    free_response(value)
}
#[no_mangle]
pub unsafe extern "C" fn tandemlog_text_alloc(size: usize) -> *mut u8 {
    allocate_input(size)
}
#[no_mangle]
pub unsafe extern "C" fn tandemlog_text_release_input(value: *mut u8, size: usize) {
    release_input(value, size)
}

// Original spike names remain aliases of the same worker and allocator contract.
#[no_mangle]
pub unsafe extern "C" fn spike_json(input: *const c_char) -> *mut c_char {
    json_request(input)
}
#[no_mangle]
pub unsafe extern "C" fn spike_free(value: *mut c_char) {
    free_response(value)
}
#[no_mangle]
pub unsafe extern "C" fn spike_alloc(size: usize) -> *mut u8 {
    allocate_input(size)
}
#[no_mangle]
pub unsafe extern "C" fn spike_release_input(value: *mut u8, size: usize) {
    release_input(value, size)
}

#[cfg(test)]
mod owned_undo_tests {
    use super::*;

    fn setup(text: &str) -> Engine {
        let mut engine = Engine::default();
        let seed = engine.command(json!({"op":"seed", "text":text})).unwrap();
        engine
            .command(json!({"op":"new", "name":"owner", "client":10,
            "seed":seed["update"]}))
            .unwrap();
        engine
    }

    fn replace(engine: &mut Engine, text: &str, operation: &str, actor: u64) {
        let old = engine
            .command(json!({"op":"read", "name":"owner"}))
            .unwrap();
        let old = old["text"].as_str().unwrap();
        // Synthetic ASCII titles retain their unchanged tail, as the real
        // captured editor does; peer text attaches to those stable identities.
        assert!(old.is_ascii() && text.is_ascii());
        let prefix = old
            .bytes()
            .zip(text.bytes())
            .take_while(|(a, b)| a == b)
            .count();
        let suffix = old
            .bytes()
            .rev()
            .zip(text.bytes().rev())
            .take(old.len().min(text.len()) - prefix)
            .take_while(|(a, b)| a == b)
            .count();
        engine
            .command(json!({"op":"draft", "name":"draft", "source":"owner",
            "client":actor}))
            .unwrap();
        engine
            .command(json!({"op":"edit", "name":"draft", "index":prefix,
            "delete":old.len() - prefix - suffix, "insert":&text[prefix..text.len()-suffix]}))
            .unwrap();
        let packet = engine
            .command(json!({"op":"prepare", "name":"draft",
            "target":"owner"}))
            .unwrap();
        engine
            .command(json!({"op":"cancel", "name":"draft"}))
            .unwrap();
        engine
            .command(json!({"op":"apply_owned", "name":"owner",
            "operation":operation, "update":packet["update"]}))
            .unwrap();
    }

    fn undo(engine: &mut Engine, operation: &str) -> Value {
        let prepared = engine
            .command(json!({"op":"prepare_operation_undo",
            "name":"owner", "operation":operation}))
            .unwrap();
        engine
            .command(json!({"op":"commit_undo", "name":"owner",
            "token":prepared["token"], "receipt":{"update":prepared["update"]}}))
            .unwrap();
        prepared
    }

    fn text(engine: &mut Engine) -> String {
        engine
            .command(json!({"op":"read", "name":"owner"}))
            .unwrap()["text"]
            .as_str()
            .unwrap()
            .to_owned()
    }

    #[test]
    fn successive_owned_replacements_follow_restored_identity_and_preserve_peer() {
        let mut engine = setup("Review household supplies");
        replace(&mut engine, "Check household supplies", "first", 20);
        replace(&mut engine, "Plan household supplies", "second", 30);
        let state = engine
            .command(json!({"op":"state", "name":"owner"}))
            .unwrap();
        engine
            .command(json!({"op":"new", "name":"peer", "client":40,
            "seed":state["update"]}))
            .unwrap();
        let peer = engine
            .command(json!({"op":"edit", "name":"peer", "index":23,
            "delete":0, "insert":" (peer)"}))
            .unwrap();
        engine
            .command(json!({"op":"apply", "name":"owner", "update":peer["update"]}))
            .unwrap();
        undo(&mut engine, "second");
        assert_eq!(text(&mut engine), "Check household supplies (peer)");
        undo(&mut engine, "first");
        assert_eq!(text(&mut engine), "Review household supplies (peer)");
    }

    #[test]
    fn requested_ineffective_item_never_consumes_older_owned_save() {
        let mut engine = setup("A");
        replace(&mut engine, "AX", "first", 20);
        let state = engine
            .command(json!({"op":"state", "name":"owner"}))
            .unwrap();
        engine
            .command(json!({"op":"new", "name":"draft2", "client":30,
            "seed":state["update"]}))
            .unwrap();
        let second = engine
            .command(json!({"op":"edit", "name":"draft2", "index":2,
            "delete":0, "insert":"Y"}))
            .unwrap();
        engine
            .command(
                json!({"op":"apply_owned", "name":"owner", "operation":"second",
            "update":second["update"]}),
            )
            .unwrap();
        let peer = engine
            .command(json!({"op":"edit", "name":"draft2", "index":2,
            "delete":1, "insert":""}))
            .unwrap();
        engine
            .command(json!({"op":"apply", "name":"owner", "update":peer["update"]}))
            .unwrap();
        let prepared = undo(&mut engine, "second");
        assert_eq!(
            STANDARD
                .decode(prepared["update"].as_str().unwrap())
                .unwrap(),
            vec![0, 0]
        );
        assert_eq!(text(&mut engine), "AX");
        undo(&mut engine, "first");
        assert_eq!(text(&mut engine), "A");
    }
}

#[cfg(test)]
mod worker_failure_tests {
    use super::*;
    #[test]
    fn worker_panic_quarantines_without_implicit_reset() {
        let mut quarantined = false;
        let reply = guard_command(&mut quarantined, || -> Result<Value, String> {
            panic!("synthetic worker panic")
        });
        assert!(reply["error"].as_str().unwrap().contains("quarantined"));
        assert!(quarantined);
        let invoked = std::cell::Cell::new(false);
        let second = guard_command(&mut quarantined, || {
            invoked.set(true);
            Ok(json!({"ok":true}))
        });
        assert!(second["error"].as_str().unwrap().contains("quarantined"));
        assert!(!invoked.get());
    }
    #[test]
    fn disconnected_worker_is_explicit_unknown_outcome() {
        let (sender, receiver) = std::sync::mpsc::channel::<OwnedRequest>();
        drop(receiver);
        let reply = request_worker(&sender, b"{}".to_vec());
        assert!(reply["error"]
            .as_str()
            .unwrap()
            .contains("worker unavailable"));
        assert!(reply["error"].as_str().unwrap().contains("outcome unknown"));
    }
}
