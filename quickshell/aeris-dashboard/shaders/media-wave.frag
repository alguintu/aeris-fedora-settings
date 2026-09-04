#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float elapsedSeconds;
    float pixelMix;
};

float lineMask(float y, float center, float halfWidth, float aa) {
    return 1.0 - smoothstep(halfWidth, halfWidth + aa, abs(y - center));
}

void main() {
    const float tau = 6.28318530718;
    vec2 p = qt_TexCoord0;
    float px = 1.0 / max(size.y, 1.0);
    float t = elapsedSeconds;

    // Closely registered but not identical: broad overlaps make pale secondary
    // colors and white, while exposed edges retain cyan, magenta, and yellow.
    float cyanY = 0.50
        + sin(p.x * tau * 1.00 + t * 0.62) * 0.060
        + sin(p.x * tau * 2.63 - t * 0.19 + 0.70) * 0.013;
    float magentaY = 0.50
        + sin(p.x * tau * 1.08 + t * 0.55 + 0.28) * 0.058
        + sin(p.x * tau * 2.17 + t * 0.16 + 2.10) * 0.014;
    float yellowY = 0.50
        + sin(p.x * tau * 0.93 + t * 0.68 - 0.25) * 0.061
        + sin(p.x * tau * 1.79 - t * 0.14 + 4.00) * 0.012;

    float cyan = lineMask(p.y, cyanY,
                          2.2 * px, 1.15 * px);
    float magenta = lineMask(p.y, magentaY,
                             2.2 * px, 1.15 * px);
    float yellow = lineMask(p.y, yellowY,
                            2.2 * px, 1.15 * px);

    vec3 waveLight = min(vec3(1.0), vec3(magenta + yellow,
                                         cyan + yellow,
                                         cyan + magenta));
    float waveCoverage = max(waveLight.r, max(waveLight.g, waveLight.b));

    // CH260 homage: an 11x11 field of quiet square perforations. A pair of
    // joined eighth notes is built from brighter cells, not an icon texture.
    vec2 inset = (p - vec2(0.075)) / 0.85;
    vec2 cells = inset * 11.0;
    ivec2 cell = ivec2(floor(cells));
    vec2 within = fract(cells) - 0.5;
    float square = 1.0 - smoothstep(0.29, 0.34, max(abs(within.x), abs(within.y)));
    bool inside = all(greaterThanEqual(inset, vec2(0.0))) && all(lessThan(inset, vec2(1.0)));
    bool note = (cell.y >= 2 && cell.y <= 3 && cell.x >= 3 && cell.x <= 7)
        || (cell.x == 3 && cell.y >= 2 && cell.y <= 7)
        || (cell.x == 7 && cell.y >= 2 && cell.y <= 6)
        || (cell.y >= 7 && cell.y <= 8 && cell.x >= 1 && cell.x <= 3)
        || (cell.y >= 6 && cell.y <= 7 && cell.x >= 5 && cell.x <= 7);
    float gridAlpha = inside ? square * (note ? 0.92 : 0.18) : 0.0;
    vec3 gridLight = vec3(gridAlpha);

    vec3 light = mix(waveLight, gridLight, pixelMix);
    float coverage = mix(waveCoverage, gridAlpha, pixelMix);
    fragColor = vec4(light, coverage) * qt_Opacity;
}
