#define DR_FLAC_IMPLEMENTATION
#include "dr_flac.h"
#define DR_MP3_IMPLEMENTATION
#include "dr_mp3.h"
#include "MacAmpFLACDecoder.h"
#include "MacAmpMP3Decoder.h"

#include <stdlib.h>

struct MacAmpFLACDecoder {
    drflac *flac;
};

MacAmpFLACDecoder *macamp_flac_open(const char *path) {
    if (path == NULL) return NULL;
    drflac *flac = drflac_open_file(path, NULL);
    if (flac == NULL) return NULL;
    MacAmpFLACDecoder *decoder = (MacAmpFLACDecoder *)calloc(1, sizeof(*decoder));
    if (decoder == NULL) {
        drflac_close(flac);
        return NULL;
    }
    decoder->flac = flac;
    return decoder;
}

void macamp_flac_close(MacAmpFLACDecoder *decoder) {
    if (decoder == NULL) return;
    if (decoder->flac != NULL) drflac_close(decoder->flac);
    free(decoder);
}

uint32_t macamp_flac_channels(const MacAmpFLACDecoder *decoder) {
    return decoder != NULL && decoder->flac != NULL ? decoder->flac->channels : 0;
}

uint32_t macamp_flac_sample_rate(const MacAmpFLACDecoder *decoder) {
    return decoder != NULL && decoder->flac != NULL ? decoder->flac->sampleRate : 0;
}

uint64_t macamp_flac_total_frames(const MacAmpFLACDecoder *decoder) {
    return decoder != NULL && decoder->flac != NULL ? decoder->flac->totalPCMFrameCount : 0;
}

int macamp_flac_seek(MacAmpFLACDecoder *decoder, uint64_t frame) {
    return decoder != NULL && decoder->flac != NULL && drflac_seek_to_pcm_frame(decoder->flac, frame);
}

uint64_t macamp_flac_read_f32(MacAmpFLACDecoder *decoder, uint64_t frames, float *interleaved_samples) {
    if (decoder == NULL || decoder->flac == NULL || interleaved_samples == NULL) return 0;
    return drflac_read_pcm_frames_f32(decoder->flac, frames, interleaved_samples);
}

struct MacAmpMP3Decoder {
    drmp3 mp3;
};

MacAmpMP3Decoder *macamp_mp3_open(const char *path) {
    if (path == NULL) return NULL;
    MacAmpMP3Decoder *decoder = (MacAmpMP3Decoder *)calloc(1, sizeof(*decoder));
    if (decoder == NULL) return NULL;
    if (!drmp3_init_file(&decoder->mp3, path, NULL)) {
        free(decoder);
        return NULL;
    }
    return decoder;
}

void macamp_mp3_close(MacAmpMP3Decoder *decoder) {
    if (decoder == NULL) return;
    drmp3_uninit(&decoder->mp3);
    free(decoder);
}

uint32_t macamp_mp3_channels(const MacAmpMP3Decoder *decoder) {
    return decoder != NULL ? decoder->mp3.channels : 0;
}

uint32_t macamp_mp3_sample_rate(const MacAmpMP3Decoder *decoder) {
    return decoder != NULL ? decoder->mp3.sampleRate : 0;
}

uint64_t macamp_mp3_total_frames(const MacAmpMP3Decoder *decoder) {
    return decoder != NULL ? drmp3_get_pcm_frame_count((drmp3 *)&decoder->mp3) : 0;
}

int macamp_mp3_seek(MacAmpMP3Decoder *decoder, uint64_t frame) {
    return decoder != NULL && drmp3_seek_to_pcm_frame(&decoder->mp3, frame);
}

uint64_t macamp_mp3_read_f32(MacAmpMP3Decoder *decoder, uint64_t frames, float *interleaved_samples) {
    if (decoder == NULL || interleaved_samples == NULL) return 0;
    return drmp3_read_pcm_frames_f32(&decoder->mp3, frames, interleaved_samples);
}
