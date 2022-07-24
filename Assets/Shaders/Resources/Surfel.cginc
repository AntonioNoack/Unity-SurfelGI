#ifndef SURFEL_CGING
#define SURFEL_CGING

float3 quatRot(float3 v, float4 q){
	return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

float3 quatRotInv(float3 v, float4 q) {
	return v - 2.0 * cross(q.xyz, cross(v, q.xyz) + q.w * v);
}

struct Surfel {
    float4 position;
    float4 rotation;
    float4 color;
    float4 colorDx;
    float4 colorDy;
    float4 data; // angle-dependence
};

#endif // SURFEL_CGING