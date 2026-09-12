# Norman IO brand assets

The approved direction is a dark graphite background, a prominent luminous N,
a minimal smart-glasses outline and a blue/cyan signal arc. No small lettering,
application name, border or pre-rounded outer corners are baked into the icon.

`norman-io-master.png` is the opaque 1024 × 1024 production master.
`norman-io.ico` contains independently resized 16, 24, 32, 48, 64, 128 and
256 pixel PNG entries for platforms that consume ICO. iOS consumes the PNG
asset catalog under `apps/RayNeoCompanion/Resources/Assets.xcassets`.

Regenerate the catalog and ICO on macOS, then validate their structure:

```sh
node scripts/export-branding.mjs
node --test scripts/branding.test.mjs
```

The exporter uses Apple's `sips` for mechanical resizing of the approved master.
Do not regenerate the creative design merely to export a new size. iPhone,
iPad and App Store entries each use their declared pixel dimensions;
`NormanIOMark` includes 1×, 2× and 3× assets for reuse within the app.

## Generation provenance

Created with the built-in imagegen tool on 2026-09-12, then copied into this
repository and resized to the production master. No fallback API key was used.
The original generation was square, 1254 pixels; the production master is 1024.

Exact generation prompt:

> Create one final production iOS app icon master for Norman IO. Square 1024x1024 image, full bleed opaque dark graphite near-black (#101820) background, no rounded outer corners (iOS applies its own mask), no phone/device mockup, no framing or labels. Design a premium ultra-simple geometric brand symbol: a bold luminous capital N integrated elegantly with a minimal smart-glasses outline, with one restrained blue-to-cyan signal arc above/right. The N is the unmistakable focal point, the glasses are a secondary subtle but legible shape. Centered compact composition with generous 16% safe margin; thick precise clean strokes, readable at 40px. Rich electric blue and cyan luminous edges, restrained gentle glow, flat front-on vector-like geometry, sophisticated and quiet, not cartoon, no 3D extrusions, no lens texture, no metallic reflections, no particles, no small text, no wordmark, no watermark. Only the N monogram is allowed as a letter. Final artwork only, not a contact sheet.

## Build integration

Both project specs list `Resources` and name the `AppIcon` set directly, so any
plain `xcodegen generate` bundles the catalog for the simulator and the device
build alike. Neither Bundle IDs, signing nor permissions change with it; device
signing stays a local edit that is never committed. `scripts/branding.test.mjs`
fails if an application target loses the catalog, or if the glasses screen names
an image the catalog does not contain.

Validation uses a separate simulator project and derived output under
`artifacts/branding`. Device validation uses a uniquely named temporary project
beside the existing project so every original relative path keeps its meaning;
its generated plists and build output remain under `artifacts/branding`.
The temporary project is removed after installation, leaving the original
project untouched.

The source scanner records the exact reviewed asset hashes. A redesigned or
otherwise changed image needs a new visual review and hash update in
`scripts/check-source.mjs`; the exporter does not approve its own output.
