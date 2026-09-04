#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    vec2 grid;
    vec2 gaps;
    float cellCount;
    float cpuLayout;
    float elapsedMs;
    float transitionMs;
    float pixelRatio;
    vec4 borderColor;
    vec4 surfaceColor;
};
layout(binding = 1) uniform sampler2D colorAtlas;

vec4 cellColor(float index) {
    float x = (index + 0.5) / cellCount;
    vec4 from = texture(colorAtlas, vec2(x, 1.0 / 6.0));
    vec4 to = texture(colorAtlas, vec2(x, 0.5));
    float remaining = texture(colorAtlas, vec2(x, 5.0 / 6.0)).r * transitionMs;
    float t = remaining > 0.0 ? clamp(elapsedMs / remaining, 0.0, 1.0) : 1.0;
    return mix(from, to, t);
}
float roundedBox(vec2 p, vec2 size, float r) {
    vec2 q = abs(p - size * 0.5) - size * 0.5 + r;
    return length(max(q, 0.0)) + min(max(q.x,q.y),0.0) - r;
}
void main() {
    vec2 p = qt_TexCoord0 * size;
    float aa = 0.5 / max(1.0, pixelRatio);
    vec4 color;
    if (cpuLayout > 0.5) {
        float dieWidth = (size.x - 10.0) * 0.5;
        float die = floor(p.x / (dieWidth + 10.0));
        vec2 coreSize = vec2((dieWidth - 3.0) * 0.5, (size.y - 9.0) * 0.25);
        vec2 withinDie = vec2(p.x - die * (dieWidth + 10.0), p.y);
        vec2 core = floor(withinDie / (coreSize + 3.0));
        vec2 local = withinDie - core * (coreSize + 3.0);
        if (die > 1.0 || core.x > 1.0 || core.y > 3.0 || any(greaterThan(local,coreSize))) {
            fragColor = vec4(0); return;
        }
        color = surfaceColor * (1.0 - smoothstep(-aa, aa, roundedBox(local, coreSize, 3.0)));
        vec2 inner = local - 1.0, innerSize = coreSize - 2.0;
        if (all(greaterThanEqual(inner,vec2(0))) && all(lessThan(inner,innerSize))) {
            float thread = step(innerSize.x * 0.5, inner.x);
            float coreIndex = core.y * 2.0 + core.x;
            float cut = min(8.0, min(innerSize.x * 0.2, innerSize.y * 0.4));
            float edge = cut + 1.0;
            if (die < 0.5 && core.x < 0.5 && core.y < 0.5) edge = inner.x + inner.y;
            if (die > 0.5 && core.x > 0.5 && core.y < 0.5) edge = innerSize.x - inner.x + inner.y;
            if (die < 0.5 && core.x < 0.5 && core.y > 2.5) edge = inner.x + innerSize.y - inner.y;
            if (die > 0.5 && core.x > 0.5 && core.y > 2.5) edge = innerSize.x - inner.x + innerSize.y - inner.y;
            float mask = smoothstep(cut - aa, cut + aa, edge);
            color = mix(color, cellColor(die * 16.0 + coreIndex * 2.0 + thread), mask);
        }
    } else {
        vec2 cellSize = (size - (grid - 1.0) * gaps) / grid;
        vec2 cell = floor(p / (cellSize + gaps));
        vec2 local = p - cell * (cellSize + gaps);
        if (any(greaterThanEqual(cell,grid)) || any(greaterThan(local,cellSize))) {
            fragColor = vec4(0); return;
        }
        float outer = 1.0 - smoothstep(-aa, aa, roundedBox(local,cellSize,2.0));
        float inner = 1.0 - smoothstep(-aa, aa, roundedBox(local - 1.0,cellSize - 2.0,1.0));
        color = mix(borderColor,cellColor(cell.y * grid.x + cell.x),inner) * outer;
    }
    fragColor = color * qt_Opacity;
}
