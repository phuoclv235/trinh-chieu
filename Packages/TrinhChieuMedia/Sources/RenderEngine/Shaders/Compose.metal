#include <metal_stdlib>
using namespace metal;

// Tham số chung cho một hình chữ nhật có texture.
// Bố cục phải khớp `QuadParams` trong Compositor.swift (48 byte).
struct QuadParams {
    float4 rect;     // x, y, rộng, cao theo điểm ảnh của khung đích, gốc ở góc trên trái
    float4 uvRect;   // u0, v0, rộng, cao trong texture (dùng để cắt khi `fill`)
    float2 target;   // kích thước khung đích theo điểm ảnh
    float opacity;   // độ mờ của cả hình
    float mixT;      // hệ số hoà tan giữa texture 0 và texture 1
};

struct QuadOut {
    float4 position [[position]];
    float2 uv;
};

// Bốn đỉnh theo thứ tự triangle strip: (0,0) (1,0) (0,1) (1,1).
vertex QuadOut quad_vertex(uint vid [[vertex_id]], constant QuadParams &p [[buffer(0)]]) {
    float2 corner = float2(float(vid & 1u), float(vid >> 1u));
    float2 pixel = p.rect.xy + corner * p.rect.zw;
    float2 ndc = float2(pixel.x / p.target.x * 2.0 - 1.0, 1.0 - pixel.y / p.target.y * 2.0);
    QuadOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.uv = p.uvRect.xy + corner * p.uvRect.zw;
    return out;
}

// Màu đã nhân sẵn alpha (premultiplied); trộn trong không gian gamma sRGB.
fragment float4 quad_fragment(QuadOut in [[stage_in]],
                              constant QuadParams &p [[buffer(0)]],
                              texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    return tex.sample(s, in.uv) * p.opacity;
}

// Hoà tan: trộn texture 0 (cảnh cũ) và texture 1 (cảnh mới) theo `mixT`.
fragment float4 dissolve_fragment(QuadOut in [[stage_in]],
                                  constant QuadParams &p [[buffer(0)]],
                                  texture2d<float> from [[texture(0)]],
                                  texture2d<float> to [[texture(1)]]) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    float4 a = from.sample(s, in.uv);
    float4 b = to.sample(s, in.uv);
    return mix(a, b, clamp(p.mixT, 0.0, 1.0)) * p.opacity;
}
