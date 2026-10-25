// nmux's three pipelines: the background, the cell backgrounds and the text, instanced per glyph. Adapted from
// Ghostty's `src/renderer/shaders/shaders.metal` at commit 22f100c6, with its `Uniforms` and `CellText` layouts.
// nmux draws into an sRGB layer and blends as macOS does, so a colour passes as it is: the Display P3 conversion,
// linear blending, minimum contrast and the images are left out, as nothing nmux draws needs them.
// Ghostty: MIT License, Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors; see vendor/LICENSE-ghostty.
#include <metal_stdlib>

using namespace metal;

struct Uniforms {
  float4x4 projection_matrix;
  float2 screen_size;
  float2 cell_size;
  ushort2 grid_size;
  float4 grid_padding;
  uint8_t padding_extend;
  float min_contrast;
  ushort2 cursor_pos;
  uchar4 cursor_color;
  uchar4 bg_color;
  bool cursor_wide;
  bool use_display_p3;
  bool use_linear_blending;
  bool use_linear_correction;
};

// A 4 byte RGBA colour, premultiplied.
float4 load_color(uchar4 in_color) {
  float4 color = float4(in_color) / 255.0f;
  color.rgb *= color.a;
  return color;
}

struct FullScreenVertexOut {
  float4 position [[position]];
};

// One triangle that covers the viewport and is clipped to it.
vertex FullScreenVertexOut full_screen_vertex(uint vid [[vertex_id]]) {
  FullScreenVertexOut out;
  out.position = float4(vid == 2 ? 3.0 : -1.0, vid == 0 ? -3.0 : 1.0, 1.0, 1.0);
  return out;
}

fragment float4 bg_color_fragment(
  FullScreenVertexOut in [[stage_in]],
  constant Uniforms& uniforms [[buffer(1)]]
) {
  return load_color(uniforms.bg_color);
}

// Each cell's own background; a cell without one, and the margin past the grid, stay transparent.
fragment float4 cell_bg_fragment(
  FullScreenVertexOut in [[stage_in]],
  constant Uniforms& uniforms [[buffer(1)]],
  constant uchar4 *cells [[buffer(2)]]
) {
  int2 grid_pos = int2(floor((in.position.xy - uniforms.grid_padding.wx) / uniforms.cell_size));
  if (grid_pos.x < 0 || grid_pos.y < 0 || grid_pos.x >= uniforms.grid_size.x || grid_pos.y >= uniforms.grid_size.y) {
    return float4(0.0);
  }
  return load_color(cells[grid_pos.y * uniforms.grid_size.x + grid_pos.x]);
}

// Ghostty's `CellTextBools`; bit 1, no minimum contrast, waits for the contrast.
enum CellTextFlags : uint8_t {
  IS_CURSOR_GLYPH = 2u,
};

struct CellText {
  // The glyph's place and size in the atlas.
  uint2 glyph_pos;
  uint2 glyph_size;
  // From the cell's left edge to the glyph's, and from the cell's bottom up to the glyph's top.
  short2 bearings;
  ushort2 grid_pos;
  uchar4 color;
  // Which atlas; nmux has only the alpha one yet.
  uint8_t atlas;
  uint8_t flags;
};

struct CellTextVertexOut {
  float4 position [[position]];
  float4 color [[flat]];
  float2 tex_coord;
};

// A quad per glyph from a triangle strip: vertex 0 top-left, 1 top-right, 2 bottom-left, 3 bottom-right.
vertex CellTextVertexOut cell_text_vertex(
  uint vid [[vertex_id]],
  uint iid [[instance_id]],
  device const CellText *glyphs [[buffer(0)]],
  constant Uniforms& uniforms [[buffer(1)]]
) {
  CellText in = glyphs[iid];
  float2 corner = float2(float(vid == 1 || vid == 3), float(vid == 2 || vid == 3));
  float2 size = float2(in.glyph_size);
  float2 offset = float2(in.bearings);
  offset.y = uniforms.cell_size.y - offset.y;
  float2 pos = uniforms.cell_size * float2(in.grid_pos) + size * corner + offset;

  CellTextVertexOut out;
  out.position = uniforms.projection_matrix * float4(pos.x, pos.y, 0.0f, 1.0f);
  // In pixels, as the sampler addresses the atlas.
  out.tex_coord = float2(in.glyph_pos) + size * corner;
  out.color = load_color(in.color);

  // Text under a block cursor takes the cursor's text colour; the cursor glyph keeps its own.
  bool is_cursor_pos = (in.grid_pos.x == uniforms.cursor_pos.x ||
                        (uniforms.cursor_wide && in.grid_pos.x == uniforms.cursor_pos.x + 1)) &&
                       in.grid_pos.y == uniforms.cursor_pos.y;
  if ((in.flags & IS_CURSOR_GLYPH) == 0 && is_cursor_pos) {
    out.color = load_color(uniforms.cursor_color);
  }
  return out;
}

// A glyph is its colour times its mask.
fragment float4 cell_text_fragment(
  CellTextVertexOut in [[stage_in]],
  texture2d<float> atlas [[texture(0)]]
) {
  constexpr sampler textureSampler(coord::pixel, address::clamp_to_edge, filter::nearest);
  return in.color * atlas.sample(textureSampler, in.tex_coord).r;
}
