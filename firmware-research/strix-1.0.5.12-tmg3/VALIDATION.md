# TMG3 127 validation

## Fixed artifacts

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Official 127 ZIP | 8769953 | b7bfd3cc73528e3e9995ad227dc877c8334d43dc8051436e2d2ccff2ca0b4133 |
| TMG3 ZIP | 8869710 | adf7a6fa6531c6246e0a067343310ac4c662ddd5b76fbe3aba457a8c4ac68c87 |
| TMG3 AP | 7515400 | 20094d589b2453ba97ac764da625e86dcc78b4f76cb00f2a5fd5cba486187f3f |
| Module | 199936 | 690371ced3c660bd6fa113dde2070295d74719990d1a7d432403d5ff5c257eb4 |

[Release assets and evidence](https://github.com/Fnckerpoi/Cheater-IO/releases/tag/strix-1.0.5.12-tmg3-20261103). The official archive is unchanged, including its original container bytes.

## Source and offline validation

The port updates lifecycle construction and destruction, Head Manager/Slot bindings, launcher publication address and renderer root/GPU/software dispatch bindings for the 127 baseline. The full module compiles from 71 primary and seven additional objects with OHOS 15 LLVM. The fixed source list, linker script, headers, assembly and animation asset are included in this directory.

The build reproduces the published ZIP byte for byte using the recorded toolchain/compression environment. `build.py --audit` independently reads the official and generated archives and checks both identities, ZIP CRC, 16 unique archive members, all 15 manifest payload sizes and MD5 values, 34 patch slots, seven unchanged startup descriptors and the appended module. Only the AP payload changes; the other 14 payloads and their manifest rows remain unchanged. Archive timestamps are fixed.

## Device observation

On 2026-11-03 the contributor tested the published TMG3 ZIP on a RayNeo iO through a separately adapted RayNeo Android 1.0.10 (258) host. The actual firmware query and extracted staging directory were checked before a single authorized update. The sender verified 239 chunks, complete AP coverage (7515400 bytes) and a type9 response. The user confirmed firmware installation and communication recovery after returning naturally to the home screen and completing result-protection confirmation. Subsequent phone status showed no pending attempt, authorization 0 and phase LOCKED. An unchanged official 127 update was also successful as a device control.

These observations establish this device/update combination, not every enhanced optical function, every device variant or a general recovery procedure. Android host changes are not included in this firmware-only contribution. The firmware build never sends OTA commands; this contribution does not enable an upstream Android OTA path. Full OTA writes include companion payloads even though custom changes are confined to AP.
