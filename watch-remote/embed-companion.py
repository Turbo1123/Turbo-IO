"""Embed a user-signed Watch app in a NEW signed host derivative; never install.

Inputs stay unchanged. No downloading, credential provisioning, firmware or OTA.
The host must already contain the public Watch addon and the caller's signature.
"""
import argparse
import datetime
import hashlib
import plistlib
import shutil
import subprocess
from pathlib import Path


def run(*args):
    return subprocess.check_output(list(map(str, args)), stderr=subprocess.DEVNULL)


def validate(host, watch, hp, wp, he, we, identity, watch_id, now):
    host_id = host['CFBundleIdentifier']
    if watch.get('WKCompanionAppBundleIdentifier') != host_id or watch.get('WKApplication') is not True:
        raise ValueError('watch_companion_mismatch')
    if watch.get('CFBundleIdentifier') != host_id + '.turbowatch':
        raise ValueError('watch_bundle_mismatch')
    for key in ('CFBundleVersion', 'CFBundleShortVersionString'):
        if not host.get(key) or host[key] != watch.get(key):
            raise ValueError('watch_version_mismatch')
    team = he.get('com.apple.developer.team-identifier')
    if not team or we.get('com.apple.developer.team-identifier') != team:
        raise ValueError('watch_team_mismatch')
    for info, profile, ent in ((host, hp, he), (watch, wp, we)):
        expected = team + '.' + info['CFBundleIdentifier']
        allowed = profile['Entitlements'].get('application-identifier')
        if ent.get('application-identifier') != expected or allowed not in (expected, team + '.*'):
            raise ValueError('profile_bundle_mismatch')
        if profile.get('TeamIdentifier') != [team] or profile['ExpirationDate'] <= now:
            raise ValueError('profile_expired_or_wrong_team')
        certs = {hashlib.sha1(c).hexdigest().upper() for c in profile['DeveloperCertificates']}
        if identity.upper() not in certs:
            raise ValueError('identity_not_in_both_profiles')
    if not watch_id or watch_id not in wp.get('ProvisionedDevices', []):
        raise ValueError('watch_not_in_profile')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    for name in ('host', 'watch', 'out'):
        p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--identity', required=True, help='Your signing certificate SHA-1')
    p.add_argument('--watch-udid', required=True, help='Your actual target Watch, not iPhone')
    a = p.parse_args()
    host, watch, out = a.host.resolve(), a.watch.resolve(), a.out.resolve()
    if out.exists() or any(root == out or root in out.parents for root in (host, watch)):
        raise ValueError('output_must_be_new_and_outside_inputs')
    if any(not x.is_dir() or x.suffix != '.app' for x in (host, watch)):
        raise ValueError('signed_app_inputs_required')
    if (host / 'Watch').exists():
        raise ValueError('existing_watch_companion_requires_manual_review')
    if len(a.identity) != 40 or any(c not in '0123456789abcdefABCDEF' for c in a.identity):
        raise ValueError('certificate_sha1_required')
    infos = [plistlib.loads((x / 'Info.plist').read_bytes()) for x in (host, watch)]
    profiles = [plistlib.loads(run('security', 'cms', '-D', '-i', x / 'embedded.mobileprovision')) for x in (host, watch)]
    ents = [plistlib.loads(run('codesign', '-d', '--entitlements', ':-', x)) for x in (host, watch)]
    validate(*infos, *profiles, *ents, a.identity, a.watch_udid, datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None))
    team = ents[0]['com.apple.developer.team-identifier']
    requirement = '=anchor apple generic and certificate leaf[subject.OU] = "' + team + '"'
    for app in (host, watch):
        run('codesign', '--verify', '--deep', '--strict', '-R', requirement, app)
    # Verify root Debug dylibs too: outer --deep is not sufficient for every layout.
    magic = {bytes.fromhex(x) for x in ('cffaedfe', 'cefaedfe', 'feedfacf', 'feedface', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}
    for file in watch.rglob('*'):
        if file.is_symlink():
            raise ValueError('watch_symlink_requires_manual_review')
        if file.is_file():
            with file.open('rb') as f:
                header = f.read(4)
            if header in magic:
                run('codesign', '--verify', '--strict', '-R', requirement, file)
    symbols = run('nm', '-g', host / 'Frameworks/TurboIOPrivateAddon.dylib')
    if any(symbol not in symbols for symbol in (b'_TIOWatchRemoteController', b'_TIOWatchGlobalConsume')):
        raise ValueError('host_missing_watch_addon')
    out.mkdir(parents=True, mode=0o700)
    app = out / 'Payload/Runner.app'
    shutil.copytree(host, app, symlinks=True)
    shutil.copytree(watch, app / 'Watch' / watch.name)
    entitlements = out / 'private-entitlements.plist'
    entitlements.write_bytes(plistlib.dumps(ents[0]))
    entitlements.chmod(0o600)
    run('codesign', '--force', '--sign', a.identity, '--entitlements', entitlements, app)
    run('codesign', '--verify', '--deep', '--strict', '-R', requirement, app)
    run('codesign', '--verify', '--deep', '--strict', '-R', requirement, app / 'Watch' / watch.name)
    ipa = out / 'TurboIO-Watch-PRIVATE.ipa'
    run('ditto', '-c', '-k', '--norsrc', '--noextattr', '--keepParent', out / 'Payload', ipa)
    ipa.chmod(0o600)
    run('unzip', '-tq', ipa)
    print('SIGNED_NOT_INSTALLED: private IPA created. Never publish signing inputs or this package.')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        raise SystemExit('Embedding failed; review input apps, profiles, versions and signing. Private subprocess output withheld.')
