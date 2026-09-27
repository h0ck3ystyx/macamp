#ifndef MACAMP_MP3_DECODER_H
#define MACAMP_MP3_DECODER_H

#include <stdint.h>

typedef struct MacAmpMP3Decoder MacAmpMP3Decoder;

MacAmpMP3Decoder *macamp_mp3_open(const char *path);
void macamp_mp3_close(MacAmpMP3Decoder *decoder);
uint32_t macamp_mp3_channels(const MacAmpMP3Decoder *decoder);
uint32_t macamp_mp3_sample_rate(const MacAmpMP3Decoder *decoder);
uint64_t macamp_mp3_total_frames(const MacAmpMP3Decoder *decoder);
int macamp_mp3_seek(MacAmpMP3Decoder *decoder, uint64_t frame);
uint64_t macamp_mp3_read_f32(MacAmpMP3Decoder *decoder, uint64_t frames, float *interleaved_samples);

#endif
