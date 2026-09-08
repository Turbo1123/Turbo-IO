#include "NativeVoiceVAD.h"
#include "opus.h"
#include "webrtc/common_audio/vad/include/webrtc_vad.h"
#include <stdlib.h>
#include <string.h>
struct RNVoiceVAD { OpusDecoder *decoder; VadInst *vad; };
int RNVoiceVADReset(RNVoiceVAD *s) {
    if (!s || !s->decoder || !s->vad) return -1;
    if (opus_decoder_ctl(s->decoder, OPUS_RESET_STATE) != OPUS_OK) return -2;
    if (WebRtcVad_Init(s->vad) != 0) return -3;
    return WebRtcVad_set_mode(s->vad, 2);
}
RNVoiceVAD *RNVoiceVADCreate(void) {
    RNVoiceVAD *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    int error = 0;
    s->decoder = opus_decoder_create(16000, 1, &error);
    if (!s->decoder || error != OPUS_OK || WebRtcVad_Create(&s->vad) != 0 || RNVoiceVADReset(s) != 0) {
        RNVoiceVADDestroy(s); return NULL;
    }
    return s;
}
void RNVoiceVADDestroy(RNVoiceVAD *s) {
    if (!s) return;
    if (s->decoder) opus_decoder_destroy(s->decoder);
    if (s->vad) WebRtcVad_Free(s->vad);
    free(s);
}
int RNVoiceDecodePCM(RNVoiceVAD *s, const uint8_t *packet, size_t length, int16_t *output, size_t capacity) {
    if (!s || !s->decoder || !packet || !output || length == 0 || length > 4096) return -10;
    if (capacity < 1920) return -14;
    int expected = opus_packet_get_nb_samples(packet, (opus_int32)length, 16000);
    if (expected <= 0 || expected > 1920 || expected % 160) return -11;
    int count = opus_decode(s->decoder, packet, (opus_int32)length, output, 1920, 0);
    if (count != expected) { memset(output, 0, 1920 * sizeof(*output)); return -12; }
    return count / 160;
}
int RNVoiceVADProcess(RNVoiceVAD *s, const uint8_t *packet, size_t length, uint32_t *mask) {
    return RNVoiceVADProcessPCM(s, packet, length, mask, NULL, 0);
}
int RNVoiceVADProcessPCM(RNVoiceVAD *s, const uint8_t *packet, size_t length, uint32_t *mask, int16_t *output, size_t capacity) {
    if (mask) *mask = 0;
    if (!s || !packet || !mask || length == 0 || length > 4096) return -10;
    if (output && capacity < 1920) return -14;
    int expected = opus_packet_get_nb_samples(packet, (opus_int32)length, 16000);
    if (expected <= 0 || expected > 1920 || expected % 160) return -11;
    opus_int16 pcm[1920] = {0};
    int count = opus_decode(s->decoder, packet, (opus_int32)length, pcm, 1920, 0);
    if (count != expected) { memset(pcm, 0, sizeof(pcm)); return -12; }
    for (int i = 0; i < count / 160; ++i) {
        int voiced = WebRtcVad_Process(s->vad, 16000, pcm + i * 160, 160);
        if (voiced < 0) { memset(pcm, 0, sizeof(pcm)); *mask = 0; return -13; }
        if (voiced) *mask |= (1u << i);
    }
    if (output) memcpy(output, pcm, (size_t)count * sizeof(*pcm));
    // No retained PCM, file writer, microphone or network APIs in this layer.
    memset(pcm, 0, sizeof(pcm));
    return count / 160;
}
