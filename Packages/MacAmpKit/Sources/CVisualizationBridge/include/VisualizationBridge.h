#ifndef VISUALIZATION_BRIDGE_H
#define VISUALIZATION_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

typedef struct VisualizationBridge VisualizationBridge;

VisualizationBridge *VisualizationBridgeCreate(void);
void VisualizationBridgeDestroy(VisualizationBridge *bridge);
void VisualizationBridgeSetActive(VisualizationBridge *bridge, bool active);
void VisualizationBridgeReset(VisualizationBridge *bridge, uint64_t epoch);
bool VisualizationBridgePush(VisualizationBridge *bridge, const float *left, const float *right,
                             uint32_t channels, uint32_t frames, double sampleRate,
                             int64_t sampleTime, uint64_t hostTime);
uint32_t VisualizationBridgePop(VisualizationBridge *bridge, float *interleaved, uint32_t capacityFrames,
                                uint64_t *sequence, uint64_t *epoch, double *sampleRate,
                                int64_t *sampleTime, uint64_t *hostTime, uint32_t *channels);
uint64_t VisualizationBridgeDroppedCount(const VisualizationBridge *bridge);

#endif
