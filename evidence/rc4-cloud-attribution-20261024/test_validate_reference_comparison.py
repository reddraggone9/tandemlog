"""Evidence-validator regressions; synthetic reports are never measurements."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('reference_validator', HERE / 'validate_reference_comparison.py')
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def fixture():
    pins = json.loads((HERE / 'reference-034a57d-pins.json').read_text())
    report = json.loads((HERE / 'linux-disposal-enforcing-performance.json').read_text())
    # Reconstruct observations from published samples solely to test the parser
    # and independent policy evaluation. These flags are synthetic test input.
    report.update(measurementCompleted=True, allPinsMatch=True, measureOnly=True)
    report.pop('error')
    report['sourcePins'] = {'/source/' + k: v for k, v in pins['sourceFiles'].items()}
    report['toolPins'] = {'/sdk/bin/cache/dart-sdk/bin/dart': pins['dartSHA256'],
                          '/stage/.dart_tool/package_config.json': 'staged-config',
                          '/native.so': pins['nativeSHA256'],
                          '/sqlite.so': pins['sqliteSHA256'],
                          '/source/tool/performance/limits-v1.json': pins['limitsSHA256']}
    report['compiledSourceAndDependencyPins'] = {
        '/source/.dart_tool/package_config.json': 'original-config',
        '/stage/.dart_tool/package_config.json': 'staged-config',
        '/stage/lib/main.dart': 'source-hash',
        '/sdk/packages/flutter/lib/widgets.dart': 'flutter-hash',
        '/sdk/bin/cache/dart-sdk/bin/utils/gen_snapshot': pins['genSnapshotSHA256'],
        '/cache/hosted/pub.dev/collection-1.19.1/lib/collection.dart': 'dependency-hash'}
    report['projectImportClosure'] = ['/stage/lib/main.dart']
    report['compiledFileSeals'] = {'lib/main.dart': {'change': 'none'}}
    pins['compiledInventory'] = validator.inventory(report)
    for attempt in report['attempts']:
        rows = []
        for action, summary in attempt['summaries'].items():
            samples = summary['warmupSamplesMs'] + summary['allSamplesMs']
            rows.extend({'action': action, 'index': index, 'warmup': index < 2,
                         'microseconds': round(value * 1000)}
                        for index, value in enumerate(samples))
        attempt['result'] = {'size': attempt['size'], 'correctnessPassed': True,
                             'limitsSHA256': pins['limitsSHA256'], 'observations': rows}
    return report, pins


class ReferenceValidatorTests(unittest.TestCase):
    def test_recomputes_retained_five_absolute_three_paired_misses(self):
        report, pins = fixture()
        result = validator.validate_report(report, pins, HERE.parents[1])
        self.assertEqual((result['absoluteFailures'], result['pairedFailures']), (5, 3))
        self.assertFalse(result['releaseGateAccepted'])
        self.assertTrue(result['packageConfigurationPathOnlyReviewRequired'])

    def test_incomplete_flags_are_not_inferred(self):
        report, pins = fixture()
        del report['measurementCompleted']
        with self.assertRaisesRegex(ValueError, 'complete uninstrumented'):
            validator.validate_report(report, pins, HERE.parents[1])

    def test_changed_sample_cannot_reuse_old_summary(self):
        report, pins = fixture()
        report['attempts'][0]['result']['observations'][2]['microseconds'] += 100000
        with self.assertRaisesRegex(ValueError, 'Absolute evaluation'):
            validator.validate_report(report, pins, HERE.parents[1])

    def test_missing_paired_comparison_is_rejected(self):
        report, pins = fixture()
        report['pairedScalingAttempts'].pop()
        with self.assertRaisesRegex(ValueError, 'Paired evaluation inventory'):
            validator.validate_report(report, pins, HERE.parents[1])

    def test_installation_root_changes_only_are_portable(self):
        report, pins = fixture()
        other = copy.deepcopy(report)
        def relocate(path):
            for old, new in (('/source/', '/work/new/'), ('/stage/', '/out/new/'),
                             ('/sdk/', '/tools/new/'), ('/cache/', '/home/lab/.pub-cache/')):
                if path.startswith(old):
                    return new + path[len(old):]
            return path
        for key in ('sourcePins', 'toolPins', 'compiledSourceAndDependencyPins'):
            other[key] = {relocate(k): v for k, v in other[key].items()}
        other['projectImportClosure'] = ['/out/new/lib/main.dart']
        self.assertEqual(validator.inventory(report), validator.inventory(other))
        validator.verify_inventory(other, pins)

    def test_dependency_byte_change_and_extra_file_are_rejected(self):
        report, pins = fixture()
        report['compiledSourceAndDependencyPins']['/cache/hosted/pub.dev/collection-1.19.1/lib/collection.dart'] = 'tampered'
        with self.assertRaisesRegex(ValueError, 'contentSHA256'):
            validator.verify_inventory(report, pins)
        report, pins = fixture()
        report['compiledSourceAndDependencyPins']['/stage/lib/extra.dart'] = 'new'
        with self.assertRaisesRegex(ValueError, 'count'):
            validator.verify_inventory(report, pins)

    def test_duplicate_normalized_package_path_is_rejected(self):
        report, _ = fixture()
        report['compiledSourceAndDependencyPins']['/other/hosted/pub.dev/collection-1.19.1/lib/collection.dart'] = 'dependency-hash'
        with self.assertRaisesRegex(ValueError, 'collision'):
            validator.inventory(report)

    def test_configuration_changes_are_reported_not_claimed_path_only(self):
        report, pins = fixture()
        report['compiledSourceAndDependencyPins']['/stage/.dart_tool/package_config.json'] = 'unreviewed'
        result = validator.verify_inventory(report, pins)
        self.assertEqual(result['packageConfigurationHashes']['staged/.dart_tool/package_config.json'], 'unreviewed')
        report['compiledSourceAndDependencyPins'].pop('/source/.dart_tool/package_config.json')
        with self.assertRaisesRegex(ValueError, 'Missing original'):
            validator.verify_inventory(report, pins)


if __name__ == '__main__':
    unittest.main()
