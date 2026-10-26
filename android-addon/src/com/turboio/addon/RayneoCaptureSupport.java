package com.turboio.addon;

/** Ambient final-text ABI is unverified on pinned 1.0.6/1.0.7. Audio dump is unrelated.
 * Keep old records intact and uploads closed until a verified producer is integrated. */
final class RayneoCaptureSupport {
    private RayneoCaptureSupport() {}
    static boolean available() { return false; }
}
