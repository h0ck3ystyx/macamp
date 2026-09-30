#ifndef MIOAMP_FLAC_DECODER_H
#define MIOAMP_FLAC_DECODER_H

#include <stdint.h>

typedef struct MioAmpFLACDecoder MioAmpFLACDecoder;

MioAmpFLACDecoder *mioamp_flac_open(const char *path);
void mioamp_flac_close(MioAmpFLACDecoder *decoder);
uint32_t mioamp_flac_channels(const MioAmpFLACDecoder *decoder);
uint32_t mioamp_flac_sample_rate(const MioAmpFLACDecoder *decoder);
uint64_t mioamp_flac_total_frames(const MioAmpFLACDecoder *decoder);
int mioamp_flac_seek(MioAmpFLACDecoder *decoder, uint64_t frame);
uint64_t mioamp_flac_read_f32(MioAmpFLACDecoder *decoder, uint64_t frames, float *interleaved_samples);

#endif
