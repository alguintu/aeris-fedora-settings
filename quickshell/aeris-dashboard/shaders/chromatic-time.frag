#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};
layout(binding = 1) uniform sampler2D redMask;
layout(binding = 2) uniform sampler2D greenMask;
layout(binding = 3) uniform sampler2D blueMask;

void main() {
    // No white face: white exists only at the three-way glyph intersection.
    vec3 light = vec3(texture(redMask, qt_TexCoord0).a,
                      texture(greenMask, qt_TexCoord0).a,
                      texture(blueMask, qt_TexCoord0).a);
    // Premultiplied output preserves antialiasing and the uncovered tile.
    float coverage = max(light.r, max(light.g, light.b));
    fragColor = vec4(light, coverage) * qt_Opacity;
}
