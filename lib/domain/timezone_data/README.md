# Frozen timezone rules

iana_2025c.dart is the exact default database released with timezone 0.11.1.
All 341 existing named-zone interpretations remain unchanged while the runtime
and deserializer receive maintenance updates. Existing zones intentionally keep
2025c political and historical limitations; a package bump must not replace them.
Its two imports alone are adapted to public initializeDatabase and
TimeZoneInitException exports. See provenance.json and the independent old-reader
fixture in test/fixtures/timezone-2025c for byte-level provenance.

iana_2026e_additional.dart contains only the exact four default2026e TZF chunks
for CST6CDT, EST5EDT, MST7MDT and PST8PDT from published timezone 0.11.2. The
5696 selected bytes hash to
157d7906210f5331f21db80763a5e85601182890ff5c2a32adb0bd4721b7047f.
The independent selection fixture and original offsets/chunk hashes are in
test/fixtures/timezone-additional-2026e. No existing-zone table is taken from 2026e.

Format support is separate from per-workspace permission. Only a successfully
admitted v4 required capability permits those four new names. Legacy/v3 workspaces
reject their admission and reservation. The resolver does not enable workspaces.
The required capability pins both complete upstream default-data hashes; the
selected new-name tables cannot change with later runtime package updates.

LICENSE and AUTHORS apply to both generated tables (identical in the two package
releases). Retain NOTICE and the timezone BSD license in binary distributions.
