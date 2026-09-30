#define DR_FLAC_IMPLEMENTATION
#include "dr_flac.h"
#define DR_MP3_IMPLEMENTATION
#include "dr_mp3.h"
#include "MioAmpFLACDecoder.h"
#include "MioAmpMP3Decoder.h"

#include <stdlib.h>

struct MioAmpFLACDecoder {
    drflac *flac;
};

MioAmpFLACDecoder *mioamp_flac_open(const char *path) {
    if (path == NULL) return NULL;
    drflac *flac = drflac_open_file(path, NULL);
    if (flac == NULL) return NULL;
    MioAmpFLACDecoder *decoder = (MioAmpFLACDecoder *)calloc(1, sizeof(*decoder));
    if (decoder == NULL) {
        drflac_close(flac);
        return NULL;
    }
    decoder->flac = flac;
    return decoder;
}

void mioamp_flac_close(MioAmpFLACDecoder *decoder) {
    if (decoder == NULL) return;
    if (decoder->flac != NULL) drflac_close(decoder->flac);
    free(decoder);
}

uint32_t mioamp_flac_channels(const MioAmpFLACDecoder *decoder) {
    return decoder != NULL && decoder->flac != NULL ? decoder->flac->channels : 0;
}

uint32_t mioamp_flac_sample_rate(const MioAmpFLACDecoder *decoder) {
    return decoder != NULL && decoder->flac != NULL ? decoder->flac->sampleRate : 0;
}

uint64_t mioamp_flac_total_frames(const MioAmpFLACDecoder *decoder) {
    return decoder != NULL && decoder->flac != NULL ? decoder->flac->totalPCMFrameCount : 0;
}

int mioamp_flac_seek(MioAmpFLACDecoder *decoder, uint64_t frame) {
    return decoder != NULL && decoder->flac != NULL && drflac_seek_to_pcm_frame(decoder->flac, frame);
}

uint64_t mioamp_flac_read_f32(MioAmpFLACDecoder *decoder, uint64_t frames, float *interleaved_samples) {
    if (decoder == NULL || decoder->flac == NULL || interleaved_samples == NULL) return 0;
    return drflac_read_pcm_frames_f32(decoder->flac, frames, interleaved_samples);
}

struct MioAmpMP3Decoder {
    drmp3 mp3;
};

MioAmpMP3Decoder *mioamp_mp3_open(const char *path) {
    if (path == NULL) return NULL;
    MioAmpMP3Decoder *decoder = (MioAmpMP3Decoder *)calloc(1, sizeof(*decoder));
    if (decoder == NULL) return NULL;
    if (!drmp3_init_file(&decoder->mp3, path, NULL)) {
        free(decoder);
        return NULL;
    }
    return decoder;
}

void mioamp_mp3_close(MioAmpMP3Decoder *decoder) {
    if (decoder == NULL) return;
    drmp3_uninit(&decoder->mp3);
    free(decoder);
}

uint32_t mioamp_mp3_channels(const MioAmpMP3Decoder *decoder) {
    return decoder != NULL ? decoder->mp3.channels : 0;
}

uint32_t mioamp_mp3_sample_rate(const MioAmpMP3Decoder *decoder) {
    return decoder != NULL ? decoder->mp3.sampleRate : 0;
}

uint64_t mioamp_mp3_total_frames(const MioAmpMP3Decoder *decoder) {
    return decoder != NULL ? drmp3_get_pcm_frame_count((drmp3 *)&decoder->mp3) : 0;
}

int mioamp_mp3_seek(MioAmpMP3Decoder *decoder, uint64_t frame) {
    return decoder != NULL && drmp3_seek_to_pcm_frame(&decoder->mp3, frame);
}

uint64_t mioamp_mp3_read_f32(MioAmpMP3Decoder *decoder, uint64_t frames, float *interleaved_samples) {
    if (decoder == NULL || interleaved_samples == NULL) return 0;
    return drmp3_read_pcm_frames_f32(&decoder->mp3, frames, interleaved_samples);
}
