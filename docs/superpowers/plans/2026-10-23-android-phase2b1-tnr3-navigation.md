# Android Phase 2b-1 — TNR3 Vector-Map Navigation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Android native navigation gains the iOS 1.0.7 / NAVS3 TNR3 mini-map on TVP2:
- real nearby roads from OpenStreetMap (Overpass);
- the AMap route highlighted;
- up to 4 road names placed where the firmware will show them;
- a scale bar and a smooth heading-up pose.

It ships with the same consent (6 requests per session, at least 60 s apart, revoked at stop) and an offline replay of the bundled public-area fixtures.

**Architecture:** iOS split, ported one-to-one.
- **`NavMapCodec`:** the firmware wire contract. It ports `nav_map.c` `tnr_body_valid`, `tnr_wrap`, `screen` and `tnr_labels`, plus the TNV1 CRC, and is checked against C goldens.
- **`RoadScene`:** the phone-side scene builder, a port of `RoadMap.m`. Pure Java; the HTTP part is isolated behind a small fetcher.
- **`NativeNavSession`:** extended with the iOS `NativeNavigation.m` TNR scheduling (QUERY probe, then SCENE2 with an atomic pose, POSE at 5 Hz, CLEAR).
- **`NavigationUI`:** the switch, consent dialog, replay and AMap location feed.

**Spec:** Parent roadmap Phase 2 row. References: `official-addon/ios107-edition/{nav_map.c,nav_map.h,RoadMap.m,NavigationRoadMap.inc,NativeNavigation.m,TNVTransport.m,tests/maps/*.json}`, `official-addon/ios107-edition/navigation-runtime-v1/nav_runtime.c` (`tn_crc`); firmware `firmware-research/strix-1.0.5.5-tvp2/src/navigation-runtime-v1` (`TN_PACKET_MAX` 4096).

## Global Constraints

- **Wire:**
  - Packet: `TNV1` v1, op, sid, seq, body length, CRC (`tn_crc` over the whole packet, with the CRC field zero at bytes 20..23) at 20, body at 32. Total ≤ 4096.
  - Ops: SCENE 7, POSE 8, CLEAR 9, SCENE2 10.
  - Body rules, verbatim from `tnr_body_valid`:
    - POSE is 12 bytes: generation ≠ 0, x/y within ±8192, heading < 360, age ≤ 4000.
    - SCENE: generation ≠ 0, range 180..700, reserved u32 0, paths 1..96, points ≤ 768, every path count ≥ 2, style ≤ 6, flags ≤ 3, layer −8..8.
    - SCENE2 adds labels ≤ 4 (40 B each, strict UTF-8 printable BMP, rendered width ≤ 104 px, zero padding) plus a trailing pose with the same generation.
- **Scene content (RoadMap.m):**
  - Projection: equirectangular around the origin, x = Δlon·111319.49·cos(lat₀), y = Δlat·111319.49. Points are in quarter metres and clipped to ±500 m.
  - Douglas-Peucker with tolerance 2 m (squared 64 in quarter-metre units).
  - Style: motorway/trunk(+link) → 0, primary* → 1, secondary* → 2, tertiary* → 3, residential/unclassified/living_street → 4, else 5. The route is style 6, layer 8, always last. Bridge flag 1, tunnel flag 2. Skip `area=yes`.
  - Paths are ranked by distance to the origin. Budget: 96 paths, 768 points, total ≤ 4064 bytes including 4 labels and the pose. Range 320.
  - Labels:
    - only from road `name` tags, unique, at most 4;
    - placed with the firmware's screen transform at the current heading, with the iOS margins (left ≥ 7, right ≤ 185, top ≥ 7, bottom ≤ 137), avoiding the marker box and scale box, at least 8 px apart;
    - the anchor closest to (96, 48) wins.
- **Refresh:**
  - Rebuild the scene when there's no scene, the origin is more than 100 m away, or the AMap segment changed.
  - Also rebuild names when ≥ 3 s have passed since the last scene and one of these holds: heading turned ≥ 30°, moved > 50 m from the origin, or no label would be visible (checked via the ported `tnr_labels`).
  - Position must be ≤ 4 s old and the frame must be `navigating`; otherwise the frame passes through unchanged.
- **Network (Overpass):**
  - Request `https://overpass-api.de/api/interpreter?data=[out:json][timeout:15][maxsize:16777216];way[highway](bbox);out tags geom;` with a bbox of ±0.006° lat (lon scaled by cos lat).
  - User-Agent `TurboIO-TNR1-private-pilot/1.0`, no redirects, HTTP 200 only, ≤ 2 MiB, ≤ 5000 elements, ≤ 40000 points; reject a reply with `remark`.
  - Only with explicit per-session consent: at most 6 requests, at least 60 s apart, prefetched when within 300 m of the coverage edge. Keep at most 2 regions; never clear the old region while a request is in flight or failing.
  - Consent is revoked when navigation stops.
  - AMap coordinates are GCJ-02; Overpass is WGS-84. iOS uses AMap's converter for OSM→GCJ and an iterative inverse for the request bbox; Android uses AMap `CoordinateConverter` (GPS→AMAP) the same way, reached by reflection like the rest of `NavigationUI`.
- **Scheduling (NativeNavigation.m):**
  - "Extended" sessions first send QUERY once.
  - With a fresh pose (≤ 4 s): if the map differs from the committed one, send SCENE2 (map + current pose + age), or SCENE without labels; otherwise send POSE when the pose changed, at least 0.2 s apart, or as a keep-alive every 1 s.
  - CLEAR when a committed map has no latest map.
  - Normal UPDATE/HEARTBEAT keep priority as now.
  - The pose deadline is 3 s, other ops 8 s.
- **Sources:** `offline-replay` (bundled fixtures, no location, no network), `amap-simulation` and `amap-realtime`. The fixtures are copied into addon assets `turboio/maps/{shenzhen,hongkong,replay}.json`; they are public-area data already published in the repo.
- **Defaults:** the road map is off by default. The UI copy matches iOS ("矢量小地图 · TNR3 试验", "启用路网", "公开区域路网回放（不定位）", "本次联网试验授权").

## Review Focus

1. **Wrong-firmware packets.** Enabling the road map while a session is active is refused (iOS asks to stop first). Scenes are only sent after the QUERY reply shows the extended runtime.
2. **Location privacy.** No network request without per-session consent. The request carries only the bbox, and the coordinates are never persisted.
3. **Coordinate mismatch.** If the GCJ↔WGS inverse doesn't converge (> 0.5 m after 6 iterations), no roads are shown ("坐标转换未收敛").
4. **Oversized or pathological OSM data** can't exceed the wire budget or the 2 MiB / 5000 / 40000 limits.
5. **Stale pose.** A pose older than 4 s is never sent as current.

---

### Task 1: NavMapCodec (wire contract)

**Files:** Create `src/com/turboio/addon/NavMapCodec.java`, `tests/navmap_golden.c` and `tests/NavMapCodecTest.java`.

**Produces:**
- `static boolean bodyValid(int op,byte[] body)`;
- `static byte[] wrap(int op,long sid,long seq,byte[] body)` (null when invalid);
- `static int textWidth(byte[] utf8,int off,int len)`;
- `static int[] screen(int px,int py,int poseX,int poseY,int heading,int range)` (firmware Q14 sine);
- `static List<int[]> labels(byte[] scene2,int poseX,int poseY,int heading)`, the firmware `tnr_labels` for a just-received scene and pose: `{x,y,width}` per visible label.

**Test:**
- The C generator writes:
  - wire files for a fixed SCENE (3 paths, mixed styles and flags), a SCENE2 with 2 labels (one ASCII, one CJK), a POSE and a CLEAR, via `tnr_wrap`;
  - a `labels.txt` with the `tnr_labels` output for the SCENE2 at three poses (heading 0, 90, 215);
  - a `validity.txt` listing ~40 crafted bodies (each rule's boundary, plus random mutations) with the C `tnr_body_valid` verdict.
- Java must produce byte-identical wires and identical label views, and agree on every verdict.

- [ ] RED.
- [ ] Implement.
- [ ] GREEN.
- [ ] **Commit** `feat(android): TNR3 nav-map wire codec`.

### Task 2: RoadScene (scene builder)

**Files:**
- Create `src/com/turboio/addon/RoadScene.java` and `tests/RoadSceneTest.java`.
- Copy `official-addon/ios107-edition/tests/maps/*.json` → `android-addon/assets/turboio/maps/`.
- Update `addon_assets.py` and the audit allowlist if they enumerate assets.

**Produces:**
- `RoadScene(Converter c)` with `interface Converter{double[] toMap(double lat,double lon);}` (WGS→GCJ).
- `boolean loadFixture(String json)` and `void installFeatures(List<Feature>,double[] bbox)`.
- `Frame decorate(Frame in,List<double[]> route,double[] position,double positionAt,double heading,Object segment,double now)`, where `Frame` carries `scene`, `scene2`, `pose`, `poseAt` and `note`.
- `boolean needsRequest(double[] wgs)` and `double[] wgs(double[] map)` (iterative inverse).

**Tests** (with `shenzhen.json` and `replay.json`):
- For 30 replay samples, `decorate` yields a SCENE and SCENE2 that `NavMapCodec.bodyValid` accepts, the route path is style 6 and last, paths ≤ 96, points ≤ 768, labels ≤ 4 and unique.
- The generation strictly increases on rebuild and is unchanged when within 100 m with the same segment and heading change < 30°.
- A position older than 4 s, or a phase other than `navigating`, passes through unchanged.
- An identity converter gives `wgs()` equal to the input; a converter that never converges gives null, and the note contains "未收敛".
- `Simplify` keeps the endpoints and drops a point within 2 m.
- `RoadStyle` mapping matches the constraint table.
- Name filtering drops control and bidi characters and caps at 104 px / 31 bytes.

- [ ] RED.
- [ ] Implement.
- [ ] GREEN.
- [ ] **Commit** `feat(android): TNR3 road scene builder with offline fixtures`.

### Task 3: Overpass fetcher

**Files:** Create `src/com/turboio/addon/RoadFetch.java` and `tests/RoadFetchTest.java`.

**Produces:**
- `static String query(double[] wgs)` (bbox string, exact iOS format, 6 decimal places);
- `static List<RoadScene.Feature> parse(byte[] body)` (null when it breaks a limit or has `remark`);
- a `Budget` class: `allow(double now)` (≤ 6, ≥ 60 s), `consent()`, `revoke()`.

The Android glue does a `HttpURLConnection` GET with no redirects, 22 s timeout, reading ≤ 2 MiB on a background thread.

**Tests:**
- The query string for a known point.
- `parse` on a synthetic 3-way response gives 3 features with lon/lat order and tags.
- `remark` → null; 5001 elements → null; a way with an invalid coordinate is dropped as a whole.
- The budget allows 6 requests 60 s apart, refuses the 7th or an early one, and refuses everything after revoke.

- [ ] RED.
- [ ] Implement.
- [ ] GREEN.
- [ ] **Commit** `feat(android): bounded Overpass road fetch with per-session consent`.

### Task 4: NativeNavSession TNR scheduling

**Files:** Modify `src/com/turboio/addon/NativeNavSession.java` and `NativeNavCodec.java` (QUERY reply flag for extended support), plus `tests/NativeNavTest.java`.

**Produces:**
- `void mapOffer(byte[] scene,byte[] scene2,byte[] pose,long poseAtMs)`;
- `boolean extended()`;
- counters `maps()` and `poses()`.

The pump order follows the constraint list. Commit bookkeeping matches iOS `finish`: SCENE commits the map and clears the pose; SCENE2 commits map and pose; POSE commits the pose; CLEAR clears both.

**Tests** (fake sender and clock):
- QUERY first.
- Then SCENE2 carrying the latest pose and an age stamped at send time.
- Then POSE only when the pose changed (≥ 0.2 s), and a 1 s keep-alive when unchanged.
- An urgent UPDATE (road or turn change) preempts the pose.
- A stale pose (> 4 s) is never sent.
- A map withdrawn (road map turned off mid-session is refused at the UI, but a null `mapOffer` while committed) sends CLEAR once.
- POSE has a 3 s deadline.
- Existing `NativeNavTest` assertions stay green.

- [ ] RED.
- [ ] Implement.
- [ ] GREEN.
- [ ] **Commit** `feat(android): TNR3 scene/pose scheduling in native navigation`.

### Task 5: NavigationUI integration

**Files:** Modify `src/com/turboio/addon/NavigationUI.java`, plus `NativeNavigation.java` if the frame plumbing lives there.

Behaviour:
- Lens card section "矢量小地图 · TNR3 试验": the road switch (refused while a session is active), "公开区域路网回放（不定位）" and "本次联网试验授权" (the iOS dialog text adapted to Android).
- The AMap location callback (already reflected in `NavigationUI`) feeds `RoadScene.decorate` with GCJ position, heading and the route coordinates, then `session.mapOffer`.
- Replay drives frames from `replay.json` at 5 Hz with no location and no network.
- Stopping navigation revokes consent and resets `RoadScene`.

Verify: `build.sh` passes, `package.mjs` 1.0.7 reports `unexpected_paths` empty, and the assets appear in the APK.

- [ ] Implement.
- [ ] Verify.
- [ ] **Commit** `feat(android): TNR3 mini-map in navigation (switch, consent, replay)`.

Device checks for the user, on TVP2:
- start the replay and see roads, names, scale and smooth heading on the lens;
- real walk navigation with consent shows nearby roads within one request;
- stopping clears it.
