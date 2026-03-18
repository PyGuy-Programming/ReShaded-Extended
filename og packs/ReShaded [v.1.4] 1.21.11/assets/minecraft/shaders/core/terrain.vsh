#version 330

#moj_import <minecraft:fog.glsl>
#moj_import <minecraft:globals.glsl>
#moj_import <minecraft:chunksection.glsl>
#moj_import <minecraft:projection.glsl>

in vec3 Position;
in vec4 Color;
in vec2 UV0;
in ivec2 UV2;
in vec3 Normal;

uniform sampler2D Sampler2;

out float sphericalVertexDistance;
out float cylindricalVertexDistance;
out vec4 vertexColor;
out vec2 texCoord0;

vec4 minecraft_sample_lightmap(sampler2D lightMap, ivec2 uv) {
    return texture(lightMap, clamp((uv / 256.0) + 0.5 / 16.0, vec2(0.5 / 16.0), vec2(15.5 / 16.0)));
}

void main() {
    vec3 pos = Position + (ChunkPosition - CameraBlockPos) + CameraOffset;
    gl_Position = ProjMat * ModelViewMat * vec4(pos, 1.0);

    sphericalVertexDistance = fog_spherical_distance(pos);
    cylindricalVertexDistance = fog_cylindrical_distance(pos);
    
    vec4 vc = Color * minecraft_sample_lightmap(Sampler2, UV2);

    vec3 n = normalize(Normal);
    
    const float BRIGHTNESS_TOP  = 1.75; 
    const float BRIGHTNESS_SIDE  = 1.75; 
    const float BRIGHTNESS_BOTTOM = 1.1; 
    bool isCubeFace = (
        abs(n.y) > 0.1 || 
        abs(n.x) > 0.1 || 
        abs(n.z) > 0.1  
    );

    if (isCubeFace) {
        float faceShade = BRIGHTNESS_TOP; 

        if (n.y > 0.5) {
            faceShade = BRIGHTNESS_TOP;
        }
        else if (n.y < -0.5) {
            faceShade = BRIGHTNESS_BOTTOM;
        }
        else if (abs(n.x) > 0.5 || abs(n.z) > 0.5) {
            faceShade = BRIGHTNESS_SIDE;
        }

        vc.rgb *= faceShade;
    }

    vertexColor = vc;
    texCoord0 = UV0;
}

//by DR7 https://modrinth.com/user/DR7