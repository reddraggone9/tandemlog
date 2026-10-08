//! A bounded allow-list for the pinned Yrs 0.28 V1 wire format, not a CRDT.
//! Ordering, integration, pending dependencies and Undo remain engine-owned.
//! We inspect every struct before applying it, including hidden/pending data.
use std::collections::HashMap;
use yrs::encoding::read::Read;
use yrs::updates::decoder::{Decoder, DecoderV1};

type Id = (u64, u32);
#[derive(Debug, PartialEq, Eq)]
struct Unit {
    value: u16,
    left: Option<Id>,
    right: Option<Id>,
}
pub struct Admission {
    units: HashMap<Id, Unit>,
}
impl Admission {
    pub fn struct_actors(&self) -> Vec<u64> {
        let mut actors: Vec<_> = self.units.keys().map(|(actor, _)| *actor).collect();
        actors.sort_unstable();
        actors.dedup();
        actors
    }
    pub fn parse_with_budgets(bytes: &[u8], limit: usize, unit_cap: usize) -> Result<Self, String> {
        if bytes.is_empty() || bytes.len() > limit {
            return Err("admission packet budget exceeded".into());
        }
        let mut d = DecoderV1::from(bytes);
        let mut units = HashMap::new();
        let clients = count(&mut d, unit_cap)?;
        let mut work = 0usize;
        let mut seen_clients = std::collections::HashSet::new();
        let mut total = 0;
        for _ in 0..clients {
            let blocks = count(&mut d, unit_cap)?;
            total += blocks;
            if total > unit_cap {
                return Err("struct count limit".into());
            }
            let client = actor(&mut d)?;
            if !seen_clients.insert(client) {
                return Err("duplicate actor section".into());
            }
            let mut clock: u32 = d.read_var().map_err(err)?;
            for _ in 0..blocks {
                let info = d.read_info().map_err(err)?;
                if info == 10 {
                    // Skip is a causal hole, not content. Pending full states
                    // can contain it; Yrs owns its integration semantics.
                    let len = count(&mut d, unit_cap)?;
                    work = work.checked_add(len).ok_or("admission work budget")?;
                    if work > unit_cap {
                        return Err("admission work budget".into());
                    }
                    if len == 0 {
                        return Err("empty skip".into());
                    }
                    clock = clock.checked_add(len as u32).ok_or("clock overflow")?;
                    continue;
                }
                // String content only. Reject embeds, format, map slots,
                // nested/shared types, GC/erased content and reserved flags.
                // skip_gc retains original identity for duplicate checking.
                if info & 0x3f != 4 {
                    return Err("only unformatted plain-text structs are admitted".into());
                }
                let mut left = if info & 0x80 != 0 {
                    Some(id(&mut d)?)
                } else {
                    None
                };
                let right = if info & 0x40 != 0 {
                    Some(id(&mut d)?)
                } else {
                    None
                };
                if left.is_none() && right.is_none() {
                    let named: u32 = d.read_var().map_err(err)?;
                    if named != 1 || d.read_string().map_err(err)? != "text" {
                        return Err("only the named text root is admitted".into());
                    }
                }
                let content = d.read_string().map_err(err)?;
                if content.is_empty() {
                    return Err("empty text struct".into());
                }
                let content_units = content.encode_utf16().count();
                if content_units > unit_cap.saturating_sub(units.len()) {
                    return Err("admission identity budget".into());
                }
                for value in content.encode_utf16() {
                    if units.len() >= unit_cap {
                        return Err("retained text identity limit".into());
                    }
                    let at = (client, clock);
                    let unit = Unit { value, left, right };
                    if units.insert(at, unit).is_some() {
                        return Err("duplicate struct identity".into());
                    }
                    left = Some(at);
                    clock = clock.checked_add(1).ok_or("clock overflow")?;
                }
            }
        }
        // Parse the delete set too: bound work/ranges and reject trailing data.
        let deletes = count(&mut d, unit_cap)?;
        let mut seen_deletes = std::collections::HashSet::new();
        total = 0;
        for _ in 0..deletes {
            let client = actor(&mut d)?;
            if !seen_deletes.insert(client) {
                return Err("duplicate delete actor".into());
            }
            let ranges = count(&mut d, unit_cap)?;
            total += ranges;
            if total > unit_cap {
                return Err("delete count limit".into());
            }
            for _ in 0..ranges {
                let start: u32 = d.read_var().map_err(err)?;
                let len: u32 = d.read_var().map_err(err)?;
                if len == 0 || start.checked_add(len).is_none() {
                    return Err("invalid delete range".into());
                }
            }
        }
        if !d.read_to_end().map_err(err)?.is_empty() {
            return Err("trailing update bytes".into());
        }
        let result = Self { units };
        result.validate_seed()?;
        Ok(result)
    }
    fn validate_seed(&self) -> Result<(), String> {
        // A shared historical seed has actor 1, a contiguous span from zero,
        // and no external insertion origins. Whole or partial repeats may
        // be admitted later only against an established immutable frontier.
        for (&(actor, clock), unit) in &self.units {
            if actor == 1
                && (unit.right.is_some() || unit.left != clock.checked_sub(1).map(|c| (1, c)))
            {
                return Err("invalid historical seed origins".into());
            }
        }
        Ok(())
    }
    pub fn check_initial(&self) -> Result<(), String> {
        let count = self.units.keys().filter(|(a, _)| *a == 1).count() as u32;
        for c in 0..count {
            if !self.units.contains_key(&(1, c)) {
                return Err("incomplete historical seed".into());
            }
        }
        Ok(())
    }
    pub fn check_combined(&self, known: &Self, cap: usize) -> Result<(), String> {
        let additional = self
            .units
            .keys()
            .filter(|id| !known.units.contains_key(id))
            .count();
        if additional > cap.saturating_sub(known.units.len()) {
            return Err("admission combined identity budget".into());
        }
        self.check_against(known)
    }
    pub fn check_against(&self, known: &Self) -> Result<(), String> {
        for (id, unit) in &self.units {
            match known.units.get(id) {
                Some(old) if old != unit => return Err("conflicting actor/clock content".into()),
                None if id.0 == 1 => return Err("historical seed identity cannot extend".into()),
                _ => {}
            }
        }
        Ok(())
    }
    /// Publish identities only after the caller validates the complete delta.
    /// Disposable materializers discard their handle on any integration error.
    pub fn merge_validated(&mut self, incoming: Self) {
        self.units.extend(incoming.units);
    }
}
fn err(e: yrs::encoding::read::Error) -> String {
    format!("invalid admission packet: {e}")
}
fn count(d: &mut DecoderV1<'_>, limit: usize) -> Result<usize, String> {
    let n: u32 = d.read_var().map_err(err)?;
    if n as usize > limit {
        return Err("admission count limit".into());
    }
    Ok(n as usize)
}
fn actor(d: &mut DecoderV1<'_>) -> Result<u64, String> {
    let a: u64 = d.read_var().map_err(err)?;
    if a == 0 || a >= (1 << 53) {
        return Err("invalid wire actor".into());
    }
    Ok(a)
}
fn id(d: &mut DecoderV1<'_>) -> Result<Id, String> {
    Ok((actor(d)?, d.read_var().map_err(err)?))
}
