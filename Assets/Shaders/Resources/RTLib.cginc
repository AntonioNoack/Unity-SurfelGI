#ifndef RTLIB_CGINC
#define RTLIB_CGINC

#include "UnityRaytracingMeshUtils.cginc"
#include "Common.cginc"
#include "Random.cginc"
#include "Surfel.cginc"

#ifndef SHADER_STAGE_COMPUTE
// raytracing scene
RaytracingAccelerationStructure _RaytracingAccelerationStructure;
#endif

#define RAYTRACING_OPAQUE_FLAG      0x0f
#define RAYTRACING_TRANSPARENT_FLAG 0xf0

#define PI 3.141592653589793
#define TAU 6.283185307179586

// max recursion depth
static const uint gMaxDepth = 8;

struct RayPayload {
	// Color of the ray
	float3 color;
	float4 colorDx, colorDz;
	// Random Seed
	uint randomSeed;
	// Recursion depth
	uint depth;
	// Distance to the first hit
	float distance;
	int withinGlassDepth;
	float3 pos, dir;
	float weight;
	float4 surfelRotation;
	float surfelSize;
	int surfelId; // -1 = nothing

	// gradient path tracing
	float3 emissive;
};

// Triangle attributes
struct AttributeData {
	// Barycentric value of the intersection
	float2 barycentrics;
	float3 normal;
};

// many thanks to CustomPhase on Reddit for suggesting this to me:
// https://forum.unity.com/threads/runtime-generated-bump-maps-are-not-marked-as-normal-maps.413778/#post-4935776
// Unpack normal as DXT5nm (1, y, 1, x) or BC5 (x, y, 0, 1)
// Note neutral texture like "bump" is (0, 0, 1, 1) to work with both plain RGB normal and DXT5nm/BC5
float3 UnpackNormal(float4 packednormal) {
	packednormal.x *= packednormal.w;
	float3 normal;
	normal.xy = packednormal.xy * 2.0 - 1.0;
	// this could be set to 1, idk whether we need full accuracy like this
	normal.z = sqrt(1.0 - saturate(dot(normal.xy, normal.xy)));
	return normal;
}

// Macro that interpolate any attribute using barycentric coordinates
#define INTERPOLATE_RAYTRACING_ATTRIBUTE(A0, A1, A2, BARYCENTRIC_COORDINATES) (A0 * BARYCENTRIC_COORDINATES.x + A1 * BARYCENTRIC_COORDINATES.y + A2 * BARYCENTRIC_COORDINATES.z)

// Structure to fill for intersections; OS = object space
struct IntersectionVertex {
	// Object space position of the vertex
	float3 positionOS;
	// Object space normal of the vertex
	float3 normalOS;
	// Object space normal of the vertex
	float3 tangentOS;
	// UV coordinates
	float2 texCoord0;
	float2 texCoord1;
	float2 texCoord2;
	float2 texCoord3;
	// Vertex color
	float4 color;
	// Value used for LOD sampling
	float triangleArea;
	float texCoord0Area;
	float texCoord1Area;
	float texCoord2Area;
	float texCoord3Area;
};

// Fetch the intersetion vertex data for the target vertex
void FetchIntersectionVertex(uint vertexIndex, out IntersectionVertex outVertex) {
	outVertex.positionOS = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributePosition);
	outVertex.normalOS   = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeNormal);
	outVertex.tangentOS  = UnityRayTracingFetchVertexAttribute3(vertexIndex, kVertexAttributeTangent);
	outVertex.texCoord0  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord0);
	outVertex.texCoord1  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord1);
	outVertex.texCoord2  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord2);
	outVertex.texCoord3  = UnityRayTracingFetchVertexAttribute2(vertexIndex, kVertexAttributeTexCoord3);
	outVertex.color      = UnityRayTracingFetchVertexAttribute4(vertexIndex, kVertexAttributeColor);
}

void GetCurrentIntersectionVertex(AttributeData attributeData, out IntersectionVertex outVertex) {
	// Fetch the indices of the current triangle
	uint3 triangleIndices = UnityRayTracingFetchTriangleIndices(PrimitiveIndex());

	// Fetch the 3 vertices
	IntersectionVertex v0, v1, v2;
	FetchIntersectionVertex(triangleIndices.x, v0);
	FetchIntersectionVertex(triangleIndices.y, v1);
	FetchIntersectionVertex(triangleIndices.z, v2);

	// Compute the full barycentric coordinates
	float3 barycentricCoordinates = float3(1.0 - attributeData.barycentrics.x - attributeData.barycentrics.y, attributeData.barycentrics.x, attributeData.barycentrics.y);

	// Interpolate all the data
	outVertex.positionOS = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.positionOS, v1.positionOS, v2.positionOS, barycentricCoordinates);
	outVertex.normalOS   = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.normalOS, v1.normalOS, v2.normalOS, barycentricCoordinates);
	outVertex.tangentOS  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.tangentOS, v1.tangentOS, v2.tangentOS, barycentricCoordinates);
	outVertex.texCoord0  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord0, v1.texCoord0, v2.texCoord0, barycentricCoordinates);
	outVertex.texCoord1  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord1, v1.texCoord1, v2.texCoord1, barycentricCoordinates);
	outVertex.texCoord2  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord2, v1.texCoord2, v2.texCoord2, barycentricCoordinates);
	outVertex.texCoord3  = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.texCoord3, v1.texCoord3, v2.texCoord3, barycentricCoordinates);
	outVertex.color      = INTERPOLATE_RAYTRACING_ATTRIBUTE(v0.color, v1.color, v2.color, barycentricCoordinates);

	// Compute the lambda value (area computed in object space)
	outVertex.triangleArea  = length(cross(v1.positionOS - v0.positionOS, v2.positionOS - v0.positionOS));
	outVertex.texCoord0Area = abs((v1.texCoord0.x - v0.texCoord0.x) * (v2.texCoord0.y - v0.texCoord0.y) - (v2.texCoord0.x - v0.texCoord0.x) * (v1.texCoord0.y - v0.texCoord0.y));
	outVertex.texCoord1Area = abs((v1.texCoord1.x - v0.texCoord1.x) * (v2.texCoord1.y - v0.texCoord1.y) - (v2.texCoord1.x - v0.texCoord1.x) * (v1.texCoord1.y - v0.texCoord1.y));
	outVertex.texCoord2Area = abs((v1.texCoord2.x - v0.texCoord2.x) * (v2.texCoord2.y - v0.texCoord2.y) - (v2.texCoord2.x - v0.texCoord2.x) * (v1.texCoord2.y - v0.texCoord2.y));
	outVertex.texCoord3Area = abs((v1.texCoord3.x - v0.texCoord3.x) * (v2.texCoord3.y - v0.texCoord3.y) - (v2.texCoord3.x - v0.texCoord3.x) * (v1.texCoord3.y - v0.texCoord3.y));
}

void GenerateGradientRays(
	float3 surfelPos, float4 surfelRotation, float surfelSize, inout uint randomSeed,
	out float cosa, out float sina, out float distance, out float3 ray1Pos, out float3 ray2Pos
) {

	float baseAngle = TAU * nextRand(randomSeed);

	cosa = cos(baseAngle);
	sina = sin(baseAngle);

	// not too close, but also within surfel limits;
	// 0.1 is arbitrary
	// using a constant size would potentially introduce aliasing in symmetry-rich scenes
	distance = lerp(0.1, 1.0, nextRand(randomSeed));

	float wb = distance * surfelSize;
	float3 baseX = wb * quatRot(float3(1,0,0), surfelRotation);
	float3 baseZ = wb * quatRot(float3(0,0,1), surfelRotation);
	ray1Pos = surfelPos + baseX * cosa - baseZ * sina;
	ray2Pos = surfelPos + baseX * sina + baseZ * cosa;

}

void SetupGradientRayStart(inout RayDesc rayDesc, float3 origin, float3 target){
	rayDesc.Origin = origin;
	float3 direction = target - origin;
	float distance = length(direction);
	rayDesc.Direction = direction / distance;
	rayDesc.TMin = 0.001;
	rayDesc.TMax = distance * 1.01; // this is the length, where we hit the other surface; we only can miss it, if we have numerical issues
}

#endif // RTLIB_CGINC