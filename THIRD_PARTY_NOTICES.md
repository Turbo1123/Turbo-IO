# Third-party components

The root MIT license applies to original Turbo IO code, not to third-party components, vendor binaries, extracted interfaces or their trademarks.

- ZIPFoundation 0.9.20 is included as local source with its upstream LICENSE and privacy resource. The copied Swift 5.9 package manifest omits upstream test-only targets/fixtures; runtime sources are unchanged. Research builds may still resolve the pinned upstream package.
- Device builds use Opus 1.5.2 and WebRTC VAD sources from py-webrtcvad 2.0.10. Retain upstream COPYING/LICENSE files when supplying these dependencies.
- RayneoNet, RayneoLog and associated vendor frameworks are build dependencies of the device integration. They are not authored or relicensed by Turbo IO. Other included frameworks (including OpenSSL, CocoaAsyncSocket, SwiftProtobuf, CocoaLumberjack and SSZipArchive) retain their original licenses.
- Recovered interface definitions and version-specific ABI adapters are research integration material. No general SDK stability or permission for arbitrary vendor-library versions is implied.
- RayNeo and other product names identify interoperability targets; this project is not an official manufacturer release.

Before publication, check the actual dependency inventory and retain each supplied component's original notices. The presence of a component in a local development environment is not recorded here as a license grant. IPA/App distribution, signing certificates, private service credentials and user data are outside this source release.
