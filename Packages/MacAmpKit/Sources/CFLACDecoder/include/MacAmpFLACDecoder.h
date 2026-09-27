#ifndef MACAMP_FLAC_DECODER_H
#define MACAMP_FLAC_DECODER_H

#include <stdint.h>

typedef struct MacAmpFLACDecoder MacAmpFLACDecoder;

MacAmpFLACDecoder *macamp_flac_open(const char *path);
void macamp_flac_close(MacAmpFLACDecoder *decoder);
uint32_t macamp_flac_channels(const MacAmpFLACDecoder *decoder);
uint32_t macamp_flac_sample_rate(const MacAmpFLACDecoder *decoder);
uint64_t macamp_flac_total_frames(const MacAmpFLACDecoder *decoder);
int macamp_flac_seek(MacAmpFLACDecoder *decoder, uint64_t frame);
uint64_t macamp_flac_read_f32(MacAmpFLACDecoder *decoder, uint64_t frames, float *interleaved_samples);

#endif
