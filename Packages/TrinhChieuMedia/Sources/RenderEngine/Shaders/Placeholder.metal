#include <metal_stdlib>
using namespace metal;

// Giữ chỗ để gói shader được đóng vào bundle. T0.4 thay bằng shader thật.
kernel void placeholder_noop(uint tid [[thread_position_in_grid]]) {}
