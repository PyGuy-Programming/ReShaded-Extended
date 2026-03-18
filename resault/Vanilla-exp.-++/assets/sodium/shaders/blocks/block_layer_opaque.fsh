#version 330 core

#import <sodium:include/fog.glsl>
#import <sodium:include/chunk_material.glsl>

in vec4 v_Color;
in vec2 v_TexCoord;
in vec2 v_FragDistance;
in float fadeFactor;

// Needed for custom shading logic
in vec3 v_WorldPos; 

flat in uint v_Material;

uniform sampler2D u_BlockTex;

uniform vec4 u_FogColor;
uniform vec2 u_EnvironmentFog;
uniform vec2 u_RenderFog;
uniform vec2 u_TexelSize;
uniform bool u_UseRGSS;

out vec4 fragColor;

// ======================================================================================================== //
// ⚙️ Re-Shaded Color Settings (1.0 is the default value for each configuration) ⚙️                        //
// ======================================================================================================== //

const float BRIGHTNESS = 1.0;
const float CONTRAST_STRENGTH = 1.0;
const float SATURATION_STRENGTH = 1.0;
const float SUN_BRIGHTNESS = 1.0;

// ======================================================================================================== //
// ✅ To save your settings, save this file and press F3+T in your world (or Fn+F3+T on some laptops) ✅    //
// ======================================================================================================== //

vec3 applyVibrance(vec3 color, float vibranceStrength) {
    float luminance = dot(color, vec3(0.3));
    float maxChannel = max(max(color.r, color.g), color.b);
    float minChannel = min(min(color.r, color.g), color.b);
    float saturation = maxChannel - minChannel;
    float vibranceFactor = (1.0 - saturation) * vibranceStrength;
    vec3 gray = vec3(luminance);
    return mix(gray, color, 1.0 + vibranceFactor);
}

vec3 reduceOverbrightWhites(vec3 color) {
    float luminance = dot(color, vec3(0.333));
    float maxC = max(max(color.r, color.g), color.b);
    float minC = min(min(color.r, color.g), color.b);
    float saturation = maxC - minC;
    float whiteFactor = smoothstep(0.2, 1.0, luminance) * (1.0 - smoothstep(0.0, 1.0, saturation));
    color *= mix(1.0, 0.9, whiteFactor);
    return color;
}

vec3 adjustPixelLuminanceGradient(vec3 color) {
    float brightness = dot(color, vec3(0.333));
    float distance = abs(brightness - 0.325);
    float falloff = 1.0 - smoothstep(0.0, 0.65, distance);
    float boost = mix(1.0, 1.9, falloff);
    return clamp(color * boost, 0.0, 1.0);
}

vec3 increaseContrastByLuminance(vec3 color) {
    float luminance = dot(color, vec3(0.333));
    float overFactor = smoothstep(0.0, 2.5 * CONTRAST_STRENGTH, luminance);
    float underFactor = 1.0 - smoothstep(0.0, 0.35, luminance);
    vec3 brighter = mix(color, vec3(1.0), overFactor * 2);
    vec3 darker = mix(color, vec3(0.0), underFactor * 0.1);
    return mix(darker, brighter, overFactor);
}

vec4 sampleNearest(sampler2D sampler, vec2 uv, vec2 pixelSize, vec2 du, vec2 dv, vec2 texelScreenSize) {
    vec2 uvTexelCoords = uv / pixelSize;
    vec2 texelCenter = round(uvTexelCoords) - 0.5f;
    vec2 texelOffset = uvTexelCoords - texelCenter;
    texelOffset = (texelOffset - 0.5f) * pixelSize / texelScreenSize + 0.5f;
    texelOffset = clamp(texelOffset, 0.0f, 1.0f);
    uv = (texelCenter + texelOffset) * pixelSize;
    return textureGrad(sampler, uv, du, dv);
}

vec4 sampleNearest(sampler2D source, vec2 uv, vec2 pixelSize) {
    vec2 du = dFdx(uv);
    vec2 dv = dFdy(uv);
    vec2 texelScreenSize = sqrt(du * du + dv * dv);
    return sampleNearest(source, uv, pixelSize, du, dv, texelScreenSize);
}

vec4 sampleRGSS(sampler2D source, vec2 uv, vec2 pixelSize) {
    vec2 du = dFdx(uv);
    vec2 dv = dFdy(uv);
    vec2 texelScreenSize = sqrt(du * du + dv * dv);
    float maxTexelSize = max(texelScreenSize.x, texelScreenSize.y);
    float minPixelSize = min(pixelSize.x, pixelSize.y);
    float transitionStart = minPixelSize * 1.0;
    float transitionEnd = minPixelSize * 2.0;
    float blendFactor = smoothstep(transitionStart, transitionEnd, maxTexelSize);
    float duLength = length(du);
    float dvLength = length(dv);
    float minDerivative = min(duLength, dvLength);
    float maxDerivative = max(duLength, dvLength);
    float effectiveDerivative = sqrt(minDerivative * maxDerivative);
    float mipLevelExact = max(0.0, log2(effectiveDerivative / minPixelSize));
    const vec2 offsets[4] = vec2[](
    vec2(0.125, 0.375),
    vec2(-0.125, -0.375),
    vec2(0.375, -0.125),
    vec2(-0.375, 0.125)
    );
    vec4 rgssColor = vec4(0.0);
    for (int i = 0; i < 4; ++i) {
        vec2 sampleUV = uv + offsets[i] * pixelSize;
        rgssColor += textureLod(source, sampleUV, mipLevelExact);
    }
    rgssColor *= 0.25;
    vec4 nearestColor = sampleNearest(source, uv, pixelSize, du, dv, texelScreenSize);
    return mix(nearestColor, rgssColor, blendFactor);
}

void main() {
    vec4 texColor = u_UseRGSS ? sampleRGSS(u_BlockTex, v_TexCoord, u_TexelSize) : sampleNearest(u_BlockTex, v_TexCoord, u_TexelSize);
    vec4 baseVertexColor = v_Color;

    vec3 fdx = dFdx(v_WorldPos);
    vec3 fdy = dFdy(v_WorldPos);
    vec3 n = normalize(cross(fdx, fdy));

    bool isPlant = (abs(n.x) > 0.3 && abs(n.z) > 0.3);

    vec3 geometryShade = vec3(1.0);
    
    float lit = 1.85 * SUN_BRIGHTNESS;
    float litSide = 2.7 * SUN_BRIGHTNESS;
    float dark = 1.9;
    
    float plantBrightness = 1.7 * SUN_BRIGHTNESS;

    float blockLum = dot(texColor.rgb, vec3(0.299, 0.587, 0.114));

    vec3 baseSunTint = vec3(1.15, 1.10, 1.08);

    float sunIntensity = smoothstep(0.0, 0.5, blockLum) * (1.0 - smoothstep(0.5, 1.0, blockLum));

    vec3 sunTint = mix(vec3(1.0), baseSunTint, sunIntensity);

    if (isPlant) {
        geometryShade = vec3(plantBrightness) * sunTint;
    } else {
        geometryShade = vec3(lit);
        
        if (n.y < -0.5) {
            geometryShade = vec3(dark);
        } else if (n.y > 0.5) {
             geometryShade = vec3(lit) * sunTint;
        } else if (n.y < 0.5) {
            if (n.z > 0.5)       geometryShade = vec3(litSide) * sunTint;
            else if (n.z < -0.5) geometryShade = vec3(dark);
            else if (n.x > 0.5)  geometryShade = vec3(dark);
            else if (n.x < -0.5) geometryShade = vec3(litSide) * sunTint;
        }
    }

    vec3 vertexFilter = vec3(1.0);
    
    float vertexBrightness = max(max(baseVertexColor.r, baseVertexColor.g), baseVertexColor.b);

    if (vertexBrightness <= 0.65) { vertexFilter *= vec3(0.9583, 0.9752, 0.9971); }
    if (vertexBrightness <= 0.645) { vertexFilter *= vec3(0.9583, 0.9752, 0.9971); }
    if (vertexBrightness <= 0.64) { vertexFilter *= vec3(0.9583, 0.9752, 0.9971); }
    if (vertexBrightness <= 0.635) { vertexFilter *= vec3(0.9583, 0.9752, 0.9971); }
    if (vertexBrightness <= 0.63) { vertexFilter *= vec3(0.9583, 0.9752, 0.9971); }
    if (vertexBrightness <= 0.625) { vertexFilter *= vec3(0.9583, 0.9752, 0.9971); }
    if (vertexBrightness <= 0.62) { vertexFilter *= vec3(0.9583, 0.9752, 0.9971); }
    if (vertexBrightness <= 0.615) { vertexFilter *= vec3(0.9583, 0.9752, 0.9971); }
    if (vertexBrightness <= 0.61) { vertexFilter *= vec3(0.9583, 0.9752, 0.9971); }
    if (vertexBrightness <= 0.605) { vertexFilter *= vec3(0.9583, 0.9752, 0.9971); }
    
    if (vertexBrightness <= 0.186)  { vertexFilter *= vec3(0.96473); }
    if (vertexBrightness <= 0.1885) { vertexFilter *= vec3(0.96473); }
    if (vertexBrightness <= 0.191)  { vertexFilter *= vec3(0.96473); }
    if (vertexBrightness <= 0.1935) { vertexFilter *= vec3(0.96473); }
    if (vertexBrightness <= 0.196)  { vertexFilter *= vec3(0.96473); }
    if (vertexBrightness <= 0.1985) { vertexFilter *= vec3(0.96473); }
    if (vertexBrightness <= 0.201)  { vertexFilter *= vec3(0.96473); }
    if (vertexBrightness <= 0.2035) { vertexFilter *= vec3(0.96473); }
    if (vertexBrightness <= 0.206)  { vertexFilter *= vec3(0.96473); }
    if (vertexBrightness <= 0.2085) { vertexFilter *= vec3(0.96473); }

    if (vertexBrightness <= 0.2)  { vertexFilter *= vec3(1.056); }
    if (vertexBrightness <= 0.18) { vertexFilter *= vec3(1.056); }
    if (vertexBrightness <= 0.16) { vertexFilter *= vec3(1.056); }
    if (vertexBrightness <= 0.14) { vertexFilter *= vec3(1.056); }
    if (vertexBrightness <= 0.12) { vertexFilter *= vec3(1.056); }
    if (vertexBrightness <= 0.10) { vertexFilter *= vec3(1.056); }
    if (vertexBrightness <= 0.08) { vertexFilter *= vec3(1.056); }
    if (vertexBrightness <= 0.06) { vertexFilter *= vec3(1.056); }
    if (vertexBrightness <= 0.04) { vertexFilter *= vec3(1.056); }
    if (vertexBrightness <= 0.02) { vertexFilter *= vec3(1.056); }

    vec4 color = texColor;
    
    color *= baseVertexColor;
    color.rgb *= vertexFilter;
    color.rgb *= geometryShade;

    color.rgb *= 0.30 * BRIGHTNESS;
    color.rgb = applyVibrance(color.rgb, 0.5 * SATURATION_STRENGTH);
    color.rgb = adjustPixelLuminanceGradient(color.rgb);
    color.rgb = increaseContrastByLuminance(color.rgb);
    color.rgb = reduceOverbrightWhites(color.rgb);

    vec3 brightened = color.rgb * 1.0;
    float intensity = dot(brightened, vec3(0.299, 0.587, 0.114));
    vec3 saturated = mix(vec3(intensity), brightened, 1.0);
    
    color.rgb = saturated;

#ifdef USE_FRAGMENT_DISCARD
    if (color.a < _material_alpha_cutoff(v_Material)) {
        discard;
    }
#endif

    fragColor = _linearFog(color, v_FragDistance, u_FogColor, u_EnvironmentFog, u_RenderFog, fadeFactor);
}
//by DR7 https://modrinth.com/user/DR7