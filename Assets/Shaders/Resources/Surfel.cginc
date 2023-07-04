#ifndef SURFEL_CGING
#define SURFEL_CGING

struct Surfel {// 6 * 4 floats
    float4 position; // world position (local to world)
    float4 rotation; // local to world rotation quaternion
    float4 color; // color
    float4 data; // angle-dependence, specular, roughness; maybe material id in the future :)
};

struct AABB {// handled on GPU only -> layout doesn't matter
    float3 min;
    float3 max;
};

#endif // SURFEL_CGING