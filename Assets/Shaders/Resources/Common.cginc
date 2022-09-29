#ifndef COMMON_CGING
#define COMMON_CGING

#define PI 3.141592653589793
#define TAU 6.283185307179586

#define dot2(x) dot(x,x)

float3 quatRot(float3 v, float4 q){
	return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
}

float3 quatRotInv(float3 v, float4 q) {
	return v - 2.0 * cross(q.xyz, cross(v, q.xyz) + q.w * v);
}

#endif // COMMON_CGING