#ifndef FOG_GLSL_INCLUDED
#define FOG_GLSL_INCLUDED

const int FOG_SHAPE_SPHERICAL = 0;
const int FOG_SHAPE_CYLINDRICAL = 1;

const float STATIC_FOG_SKY_END = 384.0; 

const float ENVIRONMENTAL_DENSITY = 1.25; 
const float RENDER_DENSITY        = 1.35; 

const float ENVIRONMENTAL_START_MULT = 0.20;
const float ENVIRONMENTAL_END_MULT   = 0.96;
const float RENDER_START_MULT        = 0.20;
const float RENDER_END_MULT          = 1.00;

const vec3 FOG_TINT = vec3(0.8, 1.0, 1.2); 
const float FOG_TINT_INTENSITY = 0.8; 

float linear_fog_value(float vertexDistance, float fogStart, float fogEnd) {
    if (fogEnd <= fogStart) {
        return 0.0;
    }
    
    if (vertexDistance <= fogStart) {
        return 0.0;
    } else if (vertexDistance >= fogEnd) {
        return 1.0;
    }

    return (vertexDistance - fogStart) / (fogEnd - fogStart);
}

vec2 getFragDistance(vec3 position) {
    return vec2(max(length(position.xz), abs(position.y)), length(position));
}

float total_fog_value(float sphericalVertexDistance, float cylindricalVertexDistance,
                      float environmentalStart, float environmentalEnd,
                      float renderDistanceStart, float renderDistanceEnd) {

    // Aplicar multiplicadores y densidades personalizadas
    float envStart = environmentalStart * ENVIRONMENTAL_START_MULT;
    float envEnd   = environmentalEnd   * ENVIRONMENTAL_END_MULT;
    float rendStart = renderDistanceStart * RENDER_START_MULT;
    float rendEnd   = renderDistanceEnd   * RENDER_END_MULT;

    float environmentalFog = linear_fog_value(
        sphericalVertexDistance,
        envStart * (1.8 / ENVIRONMENTAL_DENSITY),
        envEnd   / ENVIRONMENTAL_DENSITY
    );

    float renderFog = linear_fog_value(
        cylindricalVertexDistance,
        rendStart * (1.0 / RENDER_DENSITY),
        rendEnd   / RENDER_DENSITY
    );

    return max(environmentalFog, renderFog);
}

vec4 _linearFog(vec4 fragColor, vec2 fragDistance, vec4 fogColor, vec2 environmentFog, vec2 renderFog, float fadeFactor) {
#ifdef USE_FOG
    float baseFogValue = total_fog_value(
        fragDistance.y, fragDistance.x, 
        environmentFog.x, environmentFog.y, 
        renderFog.x, renderFog.y
    );

    // Apply chunk fading (Sodium 1.21.11 requirement)
    float fogValue = max(1.0 - fadeFactor, baseFogValue);
    
    vec3 tintedFog = mix(fogColor.rgb, fogColor.rgb * FOG_TINT, FOG_TINT_INTENSITY);

    float skyHeightFactor = clamp((fragDistance.y - (STATIC_FOG_SKY_END * 0.5)) / (STATIC_FOG_SKY_END * 0.5), 0.0, 1.0);
    vec3 finalFog = mix(tintedFog, fogColor.rgb, skyHeightFactor);

    return vec4(mix(fragColor.rgb, finalFog, fogValue * fogColor.a), fragColor.a);
#else
    return fragColor;
#endif
}

#endif 

//by DR7 https://modrinth.com/user/DR7