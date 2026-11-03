# Strix 1.0.5.12 TMG3

This build reproduces TMG3 firmware from the exact official 1.0.5.12 ZIP and the OHOS 15 native LLVM toolchain. It does not connect to a device.

The [published firmware assets](https://github.com/Fnckerpoi/Cheater-IO/releases/tag/strix-1.0.5.12-tmg3-20261103) contain the unchanged official ZIP, TMG3 ZIP, SHA256SUMS and bounded validation evidence. Firmware archives and toolchains are external build inputs; this source contribution contains no vendor ZIP, APK, private signing material or compiled firmware.

## Build

```powershell
python -B firmware-research/strix-1.0.5.12-tmg3/build.py --stock <official-zip> --llvm-bin <ohos-sdk/windows/native/llvm/bin> --out <output-directory>
python -B firmware-research/strix-1.0.5.12-tmg3/build.py --stock <official-zip> --audit <output-directory/StrixOS-1.0.5.12-TurboIO-TMG3-CANDIDATE.zip>
```

The input ZIP SHA256 is `b7bfd3cc73528e3e9995ad227dc877c8334d43dc8051436e2d2ccff2ca0b4133`. The build checks the source pins, module, AP, archive, 34 patch slots, seven startup descriptors and unchanged companion payloads against `build-inputs.json`. It writes build products and `audit.json` to the requested output directory; it does not update the pins.

The repaired module is 199,936 bytes, SHA256 `690371ced3c660bd6fa113dde2070295d74719990d1a7d432403d5ff5c257eb4`; its AP is 7,515,400 bytes, SHA256 `20094d589b2453ba97ac764da625e86dcc78b4f76cb00f2a5fd5cba486187f3f`. The flashed ZIP SHA256 is `adf7a6fa6531c6246e0a067343310ac4c662ddd5b76fbe3aba457a8c4ac68c87`. ZIP entries use the fixed timestamp 2026-11-03 00:00:00; compression implementation differences can change the archive bytes even when payloads match, in which case the pinned archive check fails.
