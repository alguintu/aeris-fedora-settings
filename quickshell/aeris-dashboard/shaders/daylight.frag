#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float strength;
    float hazeX;
    vec4 shaft0;
    vec4 shaft1;
    vec4 shaft2;
    vec4 shaft3;
    vec4 shaft4;
    vec4 shaft5;
};

vec4 over(vec4 below, vec3 rgb, float alpha) {
    return vec4(rgb * alpha, alpha) + below * (1.0 - alpha);
}

float mist(vec2 p, vec2 center, vec2 radius, float density) {
    float d = length((p - center) / radius);
    return d < density ? mix(1.0, 0.75, d / density)
        : mix(0.75, 0.0, clamp((d - density) / (1.0 - density), 0.0, 1.0));
}

vec4 beam(vec4 below, vec2 p, vec4 shaft) {
    float distance = p.y + 180.0;
    float crossSection = abs(p.x - shaft.x - distance * shaft.y) / (distance * shaft.z);
    if (crossSection >= 1.0) return below;
    float along = (p.y + 60.0) / 430.0;
    vec3 color;
    float fade;
    if (along < 0.32) {
        float u = along / 0.32;
        color = mix(vec3(255,240,195), vec3(250,234,195), u);
        fade = mix(1.0, 0.88, u);
    } else if (along < 0.7) {
        float u = (along - 0.32) / 0.38;
        color = mix(vec3(250,234,195), vec3(239,227,200), u);
        fade = mix(0.88, 0.40, u);
    } else {
        color = vec3(239,227,200);
        fade = mix(0.40, 0.0, (along - 0.7) / 0.3);
    }
    // Continuous equivalent of 24 translucent Gaussian shells. Smooth edges,
    // no CPU paths, and no per-fragment trigonometry or multi-pass blur.
    float density = exp(-4.0 * crossSection * crossSection);
    float alpha = 1.0 - exp(-density * shaft.w * strength * fade);
    return over(below, color / 255.0, alpha);
}

void main() {
    vec2 p = qt_TexCoord0 * vec2(480.0, 206.0);
    vec4 result = over(vec4(0), vec3(250,235,200) / 255.0,
        mist(p, vec2(295,-95), vec2(360,290), 0.08) * 0.15 * strength);
    result = beam(result, p, shaft0);
    result = beam(result, p, shaft1);
    result = beam(result, p, shaft2);
    result = beam(result, p, shaft3);
    result = beam(result, p, shaft4);
    result = beam(result, p, shaft5);
    result = over(result, vec3(239,228,202) / 255.0,
        mist(p, vec2(hazeX,170), vec2(270,85), 0.1) * 0.06 * strength);
    fragColor = result * qt_Opacity;
}
