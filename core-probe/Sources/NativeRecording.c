#include "NativeVoiceVAD.h"
#include "opus.h"
#include <stdio.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <string.h>
#include <stdlib.h>
static void le32(unsigned char *b, uint32_t n) { for (int i=0;i<4;i++) b[i]=(unsigned char)(n>>(8*i)); }
int RNRecordingRawToWAV(const char *source, const char *destination) {
    if (!source || !destination) return -1;
    int src = open(source, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    if (src < 0) return -2;
    struct stat st;
    if (fstat(src,&st) || !S_ISREG(st.st_mode) || st.st_size<=0 || st.st_size>24*1024*1024 || st.st_size%240) { close(src); return -3; }
    FILE *in = fdopen(src,"rb"); if (!in) { close(src); return -4; }
    int dst = open(destination,O_CREAT|O_EXCL|O_WRONLY,0600);
    if (dst<0) { fclose(in); return -5; }
    FILE *out=fdopen(dst,"wb"); if (!out) { close(dst); fclose(in); return -6; }
    int error=0, result=-7; OpusDecoder *decoder=opus_decoder_create(48000,2,&error);
    unsigned char header[44]={0}, packet[240]; opus_int16 pcm[960*2]; uint32_t written=0; int skip=312;
    if (!decoder || error!=OPUS_OK) goto done;
    if (fwrite(header,1,44,out)!=44) goto done;
    for (off_t offset=0;offset<st.st_size;offset+=240) {
        if (fread(packet,1,240,in)!=240) goto done;
        int any=0; for (int i=0;i<240;i++) any|=packet[i]; if (!any) goto done;
        if (opus_packet_get_nb_samples(packet,240,48000)!=960) goto done;
        if (opus_decode(decoder,packet,240,pcm,960,0)!=960) goto done;
        const size_t bytes=(size_t)(960-skip)*2*sizeof(opus_int16);
        if (fwrite(pcm+skip*2,1,bytes,out)!=bytes) goto done;
        written+=(uint32_t)bytes; skip=0;
    }
    if (fgetc(in)!=EOF || ferror(in) || !written) goto done;
    memcpy(header,"RIFF",4); le32(header+4,written+36); memcpy(header+8,"WAVEfmt ",8);
    le32(header+16,16); header[20]=1; header[22]=2;
    le32(header+24,48000); le32(header+28,192000); header[32]=4; header[34]=16;
    memcpy(header+36,"data",4); le32(header+40,written);
    if (fseek(out,0,SEEK_SET) || fwrite(header,1,44,out)!=44 || fflush(out) || fsync(fileno(out))) goto done;
    result=0;
done:
    memset(pcm,0,sizeof(pcm)); memset(packet,0,sizeof(packet));
    if(decoder) opus_decoder_destroy(decoder);
    if(fclose(out)!=0) result=-8;
    fclose(in);
    // A failed derivative remains at this unique path, never reported as playable.
    return result;
}
