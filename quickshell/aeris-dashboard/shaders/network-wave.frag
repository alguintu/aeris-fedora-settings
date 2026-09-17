#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;
    float time;
    float receive;
    float send;
    vec4 receiveColor;
    vec4 sendColor;
};

float ribbon(vec2 p, float activity, float phase, float offset) {
    float envelope = sin(p.x * 3.14159265);
    float curve = sin(p.x * 12.56637 - phase) + 0.22 * sin(p.x * 21.9 - phase * 0.67 + offset);
    float center = 0.5 + curve * envelope * activity * 0.32;
    float distance = abs(p.y - center) * size.y;
    float core = 1.0 - smoothstep(0.65, 1.5, distance);
    float softness = exp2(-distance * distance * 0.13);
    float edge = smoothstep(0.0, 0.06, p.x) * smoothstep(0.0, 0.06, 1.0 - p.x);
    return edge * (core * 0.68 + softness * 0.20) * (0.35 + 0.65 * activity);
}
void main() {
    vec2 p = qt_TexCoord0;
    float rx = ribbon(p, receive, time * 1.6, 0.0);
    float tx = ribbon(p, send, -time * 1.2 + 1.4, 2.0);
    float alpha = max(rx, tx);
    vec3 color = (receiveColor.rgb * rx + sendColor.rgb * tx) / max(rx + tx, 0.001);
    fragColor = vec4(color * alpha, alpha) * qt_Opacity;
}
