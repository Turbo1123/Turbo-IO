"""Synthetic metadata only; no Keychain, signing tools, accounts or devices."""
import datetime
import hashlib
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('embed', Path(__file__).resolve().parents[1] / 'embed-companion.py')
embed = importlib.util.module_from_spec(spec)
spec.loader.exec_module(embed)


class MetadataTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime.datetime(2026, 1, 1)
        self.host = dict(CFBundleIdentifier='example.host', CFBundleVersion='201', CFBundleShortVersionString='1.0.5')
        self.watch = dict(self.host, CFBundleIdentifier='example.host.turbowatch', WKCompanionAppBundleIdentifier='example.host', WKApplication=True)
        self.he = {'com.apple.developer.team-identifier': 'TESTTEAM', 'application-identifier': 'TESTTEAM.example.host'}
        self.we = dict(self.he, **{'application-identifier': 'TESTTEAM.example.host.turbowatch'})
        self.hp = dict(TeamIdentifier=['TESTTEAM'], ExpirationDate=datetime.datetime(2027, 1, 1), DeveloperCertificates=[b'synthetic-certificate'], Entitlements=self.he)
        self.wp = dict(self.hp, Entitlements=self.we, ProvisionedDevices=['synthetic-watch'])
        self.identity = hashlib.sha1(b'synthetic-certificate').hexdigest()

    def check_valid(self):
        embed.validate(self.host, self.watch, self.hp, self.wp, self.he, self.we, self.identity, 'synthetic-watch', self.now)

    def test_valid(self):
        self.check_valid()

    def test_wrong_watch_device(self):
        self.wp['ProvisionedDevices'] = ['synthetic-phone']
        with self.assertRaisesRegex(ValueError, 'watch_not_in_profile'):
            self.check_valid()

    def test_mismatched_bundle_version_team_and_profile(self):
        cases = [('watch', 'WKCompanionAppBundleIdentifier', 'other'), ('watch', 'CFBundleIdentifier', 'other'),
                 ('watch', 'CFBundleVersion', '202'), ('we', 'com.apple.developer.team-identifier', 'OTHER'),
                 ('wp', 'ExpirationDate', datetime.datetime(2025, 1, 1)), ('hp', 'DeveloperCertificates', [b'wrong'])]
        for name, key, value in cases:
            with self.subTest(name=name, key=key):
                self.setUp()
                getattr(self, name)[key] = value
                with self.assertRaises(ValueError):
                    self.check_valid()


if __name__ == '__main__':
    unittest.main()
