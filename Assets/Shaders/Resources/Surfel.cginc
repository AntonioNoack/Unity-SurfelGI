#ifndef SURFEL_CGING
#define SURFEL_CGING

float3 quatRot(float3 v, float4 q){
	return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

float3 quatRotInv(float3 v, float4 q) {
	return v - 2.0 * cross(q.xyz, cross(v, q.xyz) + q.w * v);
}

struct Surfel {// 6 * 4 floats
    float4 position;
    float4 rotation;
    float4 color;
    float4 colorDx;
    float4 colorDy;
    float4 data; // angle-dependence
};

struct AABB {// handled on GPU only -> layout doesn't matter
    float3 min;
    float3 max;
};

struct Triangle {// 16 floats
    float ax,ay,az;
    float bx,by,bz;
    float cx,cy,cz;
    float r,g,b;
    float accuIndex;
    float pad0, pad1, pad2;
};

struct LightSample {// 3+3+3+1 = 10 floats
    float3 color;
    float3 surfacePos, surfaceDir;
    float weight; // = probability
};

#endif // SURFEL_CGING