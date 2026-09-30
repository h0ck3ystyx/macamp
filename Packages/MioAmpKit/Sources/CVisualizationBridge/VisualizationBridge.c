#include "VisualizationBridge.h"
#include <stdatomic.h>
#include <stdlib.h>

#define SLOT_COUNT 16u
#define MAX_FRAMES 2048u

typedef struct {
    uint64_t sequence, epoch, hostTime;
    int64_t sampleTime;
    double sampleRate;
    uint32_t channels, frames;
    float samples[MAX_FRAMES * 2u];
} Slot;

struct VisualizationBridge {
    _Atomic uint32_t readIndex, writeIndex;
    _Atomic uint64_t sequence, epoch, dropped;
    _Atomic bool active;
    Slot slots[SLOT_COUNT];
};

VisualizationBridge *VisualizationBridgeCreate(void) { return calloc(1, sizeof(VisualizationBridge)); }
void VisualizationBridgeDestroy(VisualizationBridge *bridge) { free(bridge); }
void VisualizationBridgeSetActive(VisualizationBridge *bridge, bool active) { atomic_store_explicit(&bridge->active, active, memory_order_release); }
void VisualizationBridgeReset(VisualizationBridge *bridge, uint64_t epoch) {
    atomic_store_explicit(&bridge->epoch, epoch, memory_order_release);
    uint32_t write = atomic_load_explicit(&bridge->writeIndex, memory_order_acquire);
    atomic_store_explicit(&bridge->readIndex, write, memory_order_release);
}
bool VisualizationBridgePush(VisualizationBridge *bridge, const float *left, const float *right,
                             uint32_t channels, uint32_t frames, double sampleRate,
                             int64_t sampleTime, uint64_t hostTime) {
    if (!atomic_load_explicit(&bridge->active, memory_order_acquire) || !left || frames == 0) return false;
    if (frames > MAX_FRAMES) frames = MAX_FRAMES;
    uint32_t write = atomic_load_explicit(&bridge->writeIndex, memory_order_relaxed);
    uint32_t next = (write + 1u) % SLOT_COUNT;
    uint64_t sequence = atomic_fetch_add_explicit(&bridge->sequence, 1, memory_order_relaxed) + 1;
    if (next == atomic_load_explicit(&bridge->readIndex, memory_order_acquire)) {
        atomic_fetch_add_explicit(&bridge->dropped, 1, memory_order_relaxed);
        return false;
    }
    Slot *slot = &bridge->slots[write];
    slot->sequence = sequence;
    slot->epoch = atomic_load_explicit(&bridge->epoch, memory_order_acquire);
    slot->sampleRate = sampleRate; slot->sampleTime = sampleTime; slot->hostTime = hostTime;
    slot->channels = channels > 1 && right ? 2 : 1; slot->frames = frames;
    for (uint32_t frame = 0; frame < frames; frame++) {
        slot->samples[frame * slot->channels] = left[frame];
        if (slot->channels == 2) slot->samples[frame * 2u + 1u] = right[frame];
    }
    atomic_store_explicit(&bridge->writeIndex, next, memory_order_release);
    return true;
}
uint32_t VisualizationBridgePop(VisualizationBridge *bridge, float *samples, uint32_t capacityFrames,
                                uint64_t *sequence, uint64_t *epoch, double *sampleRate,
                                int64_t *sampleTime, uint64_t *hostTime, uint32_t *channels) {
    uint32_t read = atomic_load_explicit(&bridge->readIndex, memory_order_relaxed);
    if (read == atomic_load_explicit(&bridge->writeIndex, memory_order_acquire)) return 0;
    Slot *slot = &bridge->slots[read];
    uint32_t frames = slot->frames < capacityFrames ? slot->frames : capacityFrames;
    uint32_t count = frames * slot->channels;
    for (uint32_t i = 0; i < count; i++) samples[i] = slot->samples[i];
    *sequence = slot->sequence; *epoch = slot->epoch; *sampleRate = slot->sampleRate;
    *sampleTime = slot->sampleTime; *hostTime = slot->hostTime; *channels = slot->channels;
    atomic_store_explicit(&bridge->readIndex, (read + 1u) % SLOT_COUNT, memory_order_release);
    return frames;
}
uint64_t VisualizationBridgeDroppedCount(const VisualizationBridge *bridge) { return atomic_load_explicit(&bridge->dropped, memory_order_relaxed); }
