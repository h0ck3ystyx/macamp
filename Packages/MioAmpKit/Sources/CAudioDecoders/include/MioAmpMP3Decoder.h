#ifndef MIOAMP_MP3_DECODER_H
#define MIOAMP_MP3_DECODER_H

#include <stdint.h>

typedef struct MioAmpMP3Decoder MioAmpMP3Decoder;

MioAmpMP3Decoder *mioamp_mp3_open(const char *path);
void mioamp_mp3_close(MioAmpMP3Decoder *decoder);
uint32_t mioamp_mp3_channels(const MioAmpMP3Decoder *decoder);
uint32_t mioamp_mp3_sample_rate(const MioAmpMP3Decoder *decoder);
uint64_t mioamp_mp3_total_frames(const MioAmpMP3Decoder *decoder);
int mioamp_mp3_seek(MioAmpMP3Decoder *decoder, uint64_t frame);
uint64_t mioamp_mp3_read_f32(MioAmpMP3Decoder *decoder, uint64_t frames, float *interleaved_samples);

#endif
