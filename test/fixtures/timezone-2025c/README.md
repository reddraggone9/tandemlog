# Frozen timezone0.11.1 reader and2025c fixtures

reader/lib contains the exact upstream0.11.1 relative-import runtime/data
closure. app/schedule.dart is exact a4 baseline; app/wall_time.dart changes only
two imports to that frozen package namespace and annotates each intentional
relative-lib import for the analyzer. The old reader never imports the
currently resolved timezone package. Provenance lists every original/adapted hash.
default.tzf is the exact old default database, not latest_all or10y.
names.json inventories all341 names; wall-time-vectors.json fixes independent
old-rule expected instants, gaps/folds and political/historical differences.

New reader tests compare the complete location tables against this actual
frozen reader as well as independent expected vectors. Preserve these bytes;
do not regenerate them to make a new decoder pass. No prior accepted fixture
elsewhere in the repository has been changed. LICENSE/AUTHORS/NOTICE retained.
