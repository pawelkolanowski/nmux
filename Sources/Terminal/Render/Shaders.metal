// nmux's four pipelines: the background, the cell backgrounds, the text, instanced per glyph, and the kitty images,
// one draw per placement. Adapted from Ghostty's `src/renderer/shaders/shaders.metal` at commit 22f100c6, with its
// `Uniforms`, `CellText` and `Image` layouts. nmux draws into an sRGB layer and blends as macOS does, so a colour passes
// as it is: the Display P3 conversion, linear blending and minimum contrast are left out, as nothing nmux draws needs
// them.
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

// The sRGB transfer function, from linear to encoded.
float4 unlinearize(float4 linear) {
  bool3 cutoff = linear.rgb <= 0.0031308;
  float3 lower = linear.rgb * 12.92;
  float3 higher = pow(linear.rgb, 1.0 / 2.4) * 1.055 - 0.055;
  linear.rgb = mix(higher, lower, float3(cutoff));
  return linear;
}

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

enum CellTextAtlas : uint8_t {
  ATLAS_GRAYSCALE = 0u,
  ATLAS_COLOR = 1u,
};

struct CellText {
  // The glyph's place and size in the atlas.
  uint2 glyph_pos;
  uint2 glyph_size;
  // From the cell's left edge to the glyph's, and from the cell's bottom up to the glyph's top.
  short2 bearings;
  ushort2 grid_pos;
  uchar4 color;
  // Which atlas, a CellTextAtlas.
  uint8_t atlas;
  uint8_t flags;
};

struct CellTextVertexOut {
  float4 position [[position]];
  uint8_t atlas [[flat]];
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
  out.atlas = in.atlas;
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

// A grayscale glyph is its colour times its mask. A colour glyph draws its own colours and ignores the cell's: the
// sRGB texture hands them back linear, so they are encoded again, with the alpha divided out around it.
fragment float4 cell_text_fragment(
  CellTextVertexOut in [[stage_in]],
  texture2d<float> textureGrayscale [[texture(0)]],
  texture2d<float> textureColor [[texture(1)]]
) {
  constexpr sampler textureSampler(coord::pixel, address::clamp_to_edge, filter::nearest);
  switch (in.atlas) {
    default:
    case ATLAS_GRAYSCALE:
      return in.color * textureGrayscale.sample(textureSampler, in.tex_coord).r;
    case ATLAS_COLOR: {
      float4 color = textureColor.sample(textureSampler, in.tex_coord);
      // A transparent pixel has no colour to divide out.
      if (color.a == 0.0) return color;
      color.rgb /= color.a;
      color = unlinearize(color);
      color.rgb *= color.a;
      return color;
    }
  }
}

// Ghostty's `Image`: one placement, in pixels of the terminal's cell. The source rectangle is packed, so the struct
// takes 40 bytes, as Ghostty's vertex attributes do.
struct Image {
  float2 grid_pos;
  float2 cell_offset;
  packed_float4 source_rect;
  float2 dest_size;
};

struct ImageVertexOut {
  float4 position [[position]];
  float2 tex_coord;
};

// A quad per placement from a triangle strip, corners as `cell_text_vertex`'s; the draw's base instance picks it.
vertex ImageVertexOut image_vertex(
  uint vid [[vertex_id]],
  uint iid [[instance_id]],
  device const Image *images [[buffer(3)]],
  constant Uniforms& uniforms [[buffer(1)]]
) {
  Image in = images[iid];
  float2 corner = float2(float(vid == 1 || vid == 3), float(vid == 2 || vid == 3));
  float4 source = float4(in.source_rect);

  ImageVertexOut out;
  // In pixels, as the sampler addresses the image.
  out.tex_coord = source.xy + source.zw * corner;
  float2 image_pos = uniforms.cell_size * in.grid_pos + in.cell_offset + in.dest_size * corner;
  out.position = uniforms.projection_matrix * float4(image_pos.x, image_pos.y, 0.0f, 1.0f);
  return out;
}

// The sRGB texture hands the pixel back linear; it is encoded again, then premultiplied.
fragment float4 image_fragment(
  ImageVertexOut in [[stage_in]],
  texture2d<float> image [[texture(2)]]
) {
  constexpr sampler textureSampler(coord::pixel, address::clamp_to_edge, filter::linear);
  float4 rgba = unlinearize(image.sample(textureSampler, in.tex_coord));
  rgba.rgb *= rgba.a;
  return rgba;
}
