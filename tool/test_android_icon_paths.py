"""Android vector paths require numeric parameter groups, unlike compact SVG arc flags."""
from pathlib import Path
import re
import unittest
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ANDROID = '{http://schemas.android.com/apk/res/android}'
# Android framework PathParser extracts float tokens before interpreting verbs.
# SVG's adjacent flag characters (00) therefore form one float on Android.
# https://android.googlesource.com/platform/frameworks/base/+/android-7.1.0_r1/libs/hwui/PathParser.cpp
COMMAND = re.compile(r'([MmZzLlHhVvCcSsQqTtAa])([^MmZzLlHhVvCcSsQqTtAa]*)')
NUMBER = re.compile(r'[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?')
ARITY = dict(m=2, z=0, l=2, h=1, v=1, c=6, s=4, q=4, t=2, a=7)


def validate_android_path(data):
    for command, text in COMMAND.findall(data):
        values = NUMBER.findall(text)
        if NUMBER.sub('', text).replace(',', '').strip():
            raise ValueError('Invalid numeric path data')
        arity = ARITY[command.lower()]
        if arity == 0:
            if values:
                raise ValueError('Close path cannot have parameters')
        elif not values or len(values) % arity:
            raise ValueError(f'{command} requires groups of {arity} parameters, got {len(values)}')
        elif command.lower() == 'a':
            for offset in range(0, len(values), 7):
                if any(float(values[offset + index]) not in (0, 1) for index in (3, 4)):
                    raise ValueError('Arc flags must be zero or one')


class AndroidIconPaths(unittest.TestCase):
    def test_launcher_vectors_have_android_parameter_groups(self):
        resources = ROOT / 'android/app/src/main/res'
        paths = []
        for source in resources.glob('*/*.xml'):
            for element in ET.parse(source).iter('path'):
                if ANDROID + 'pathData' in element.attrib:
                    paths.append((source, element.attrib[ANDROID + 'pathData']))
        self.assertGreaterEqual(len(paths), 3)
        for source, data in paths:
            with self.subTest(resource=str(source.relative_to(ROOT))):
                validate_android_path(data)

    def test_compact_svg_arc_flags_are_rejected_but_separated_flags_work(self):
        with self.assertRaisesRegex(ValueError, 'requires groups of 7'):
            validate_android_path('M6 2a2 2 0 00-2 2')
        validate_android_path('M6 2a2 2 0 0 0 -2 2')


if __name__ == '__main__':
    unittest.main()
