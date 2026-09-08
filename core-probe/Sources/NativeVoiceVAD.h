#ifndef RN_NATIVE_VOICE_VAD_H
#define RN_NATIVE_VOICE_VAD_H
#include <stdint.h>
#include <stddef.h>
typedef struct RNVoiceVAD RNVoiceVAD;
RNVoiceVAD *RNVoiceVADCreate(void);
void RNVoiceVADDestroy(RNVoiceVAD *state);
int RNVoiceVADReset(RNVoiceVAD *state);
// Decode a single raw Opus packet to 16k mono PCM and classify 10ms frames.
// Returns frame count (1..12), or negative error. PCM never leaves this call.
int RNVoiceVADProcess(RNVoiceVAD *state, const uint8_t *packet, size_t length,
                      uint32_t *speech_mask);
// Explicit opt-in PCM output for the user's configured cloud ASR. Capacity is
// in samples and must be >=1920. Caller releases the buffer after enqueueing.
int RNVoiceVADProcessPCM(RNVoiceVAD *state, const uint8_t *packet, size_t length,
                         uint32_t *speech_mask, int16_t *output, size_t capacity);
// Decode only. Does NOT run WebRTC VAD; cloud ASR owns speech boundaries.
int RNVoiceDecodePCM(RNVoiceVAD *state, const uint8_t *packet, size_t length,
                     int16_t *output, size_t capacity);
// File-only ordinary-recording derivative: 240-byte/20ms Opus -> 48k stereo WAV.
// O_EXCL destination, no source deletion, no PLC/zero repair. Returns 0 on full decode.
int RNRecordingRawToWAV(const char *source, const char *destination);
#endif
