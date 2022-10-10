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

// adopted from https://answers.unity.com/questions/467614/what-is-the-source-code-of-quaternionlookrotation.html
// and JOML (Java OpenGL Math Library), Matrix3f class, setFromNormalized()

float4 normalToQuaternion(float3 v0, float3 v1, float3 v2) {
    float4 dst;
    float diag = v0.x + v1.y + v2.z;
    if (diag >= 0.0) {
        dst = float4(v1.z - v2.y, v2.x - v0.z, v0.y - v1.x, diag + 1.0);
    } else if (v0.x >= v1.y && v0.x >= v2.z) {
        dst = float4(v0.x - (v1.y + v2.z) + 1.0, v1.x + v0.y, v0.z + v2.x, v1.z - v2.y);
    } else if (v1.y > v2.z) {
        dst = float4(v1.x + v0.y, v1.y - (v2.z + v0.x) + 1.0, v2.y + v1.z, v2.x - v0.z);
    } else {
        dst = float4(v0.z + v2.x, v2.y + v1.z, v2.z - (v0.x + v1.y) + 1.0, v0.y - v1.x);
    }
    return normalize(dst);
}

float4 normalToQuaternion(float3 v1) {
    float3 v0 = dot(v1.xz, v1.xz) > 0.01 ? 
        normalize(float3(v1.z, 0, -v1.x)) : float3(1,0,0);
    float3 v2 = cross(v0, v1);
    return normalToQuaternion(v0,v1,v2);
}

float4 normalToFrame(float3 v2) {
    float3 v1 = dot(v2.xy, v2.xy) > 0.01 ? 
        normalize(float3(v2.y, -v2.x, 0)) : float3(1,0,0);
    float3 v0 = cross(v1, v2);
    return normalToQuaternion(v0,v1,v2);
}

float4 tbnToFrame(float3 v0, float3 v1, float3 v2) {
    return normalToQuaternion(v0,v1,v2);
}

#endif // COMMON_CGING