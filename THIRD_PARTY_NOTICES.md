# Third-party components

V2 (`official-addon/`) adds original extension sources and local preparation/signing tools only. No new official application executable, decrypted image, IPA, vendor framework or signing material is shipped in that directory. The official app is a user-supplied interoperability target, not a component licensed by this repository. Existing V1 dependency notices below remain unchanged.

The root PolyForm Noncommercial 1.0.0 license covers original Turbo IO material the project has authority to license, not third-party components, vendor binaries, extracted interfaces or their trademarks. Previously granted MIT permissions remain unaffected; see docs/LICENSING.md. Do not replace any upstream license with the root license.

- ZIPFoundation 0.9.20 is included as local source with its upstream LICENSE and privacy resource. The copied Swift 5.9 package manifest omits upstream test-only targets/fixtures; runtime sources are unchanged. Research builds may still resolve the pinned upstream package.
- Device builds use Opus 1.5.2 and WebRTC VAD sources from py-webrtcvad 2.0.10. Retain upstream COPYING/LICENSE files when supplying these dependencies.
- RayneoNet, RayneoLog and associated vendor frameworks are build dependencies of the device integration. They are not authored or relicensed by Turbo IO. Other included frameworks (including OpenSSL, CocoaAsyncSocket, SwiftProtobuf, CocoaLumberjack and SSZipArchive) retain their original licenses.
- Recovered interface definitions and version-specific ABI adapters are research integration material. No general SDK stability or permission for arbitrary vendor-library versions is implied.
- RayNeo and other product names identify interoperability targets; this project is not an official manufacturer release.

Before publication, check the actual dependency inventory and retain each supplied component's original notices. The presence of a component in a local development environment is not recorded here as a license grant. IPA/App distribution, signing certificates, private service credentials and user data are outside this source release.
