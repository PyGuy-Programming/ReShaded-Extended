#version 150

#moj_import <minecraft:fog.glsl>


in float vertexDistance;
in vec4 vertexColor;
in vec3 Pos;
in vec3 PlayerPos;

out vec4 fragColor;

void main() {



    vec4 color = vertexColor;

    color = mix(color, FogColor, 0.5);

    color.a *= 1.0f - linear_fog_value(vertexDistance, 0, FogCloudsEnd);

    float fadeDirection = (PlayerPos.y+5)/10;
    float fadeIntensity = abs(PlayerPos.y/40);

    float topFadeHeight = 1 - ((20-Pos.y) / 20);
    float bottomFadeHeight = 1 - (Pos.y / 20);
    float fadeHeight = mix(topFadeHeight, bottomFadeHeight, clamp(fadeDirection, 0, 1));
    float fadeFinal = mix(1.0, fadeHeight, clamp(fadeIntensity, 0, 1));


    color.a *= fadeFinal;


    fragColor = color;
}