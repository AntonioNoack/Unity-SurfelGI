Shader "RayTracing/DxrDiffuseNormal" {
	Properties { }
	SubShader {
		Tags { "RenderType" = "Opaque" }
		LOD 100

		// basic pass for GBuffer
		CGPROGRAM
		#pragma surface surf Standard fullforwardshadows

		UNITY_INSTANCING_BUFFER_START(Props)
        UNITY_INSTANCING_BUFFER_END(Props)

		struct Input {
			float2 uv_MainTex;
			float3 worldNormal;
		};
        	
		sampler2D _MainTex;

		void surf(Input input, inout SurfaceOutputStandard o) {
			o.Albedo = input.worldNormal * 0.5 + 0.5;
			o.Metallic = 0.0;
			o.Smoothness = 0.0;
			o.Alpha = 1.0;
		}
		ENDCG

		// ray tracing pass
		Pass {
			Name "DxrPass"
			Tags { "LightMode" = "DxrPass" }

			HLSLPROGRAM

			#pragma raytracing test
					   
			#include "RTLib.cginc"
			#include "Distribution.cginc"

			int _StartDepth;

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				
				rayPayload.distance = RayTCurrent();

				// stop if we have reached max recursion depth
				/*if(rayPayload.depth + 1 >= gMaxDepth) {
					return;
				}*/

				// compute vertex data on ray/triangle intersection
				IntersectionVertex currentvertex;
				GetCurrentIntersectionVertex(attributeData, currentvertex);

				// transform normal to world space
				float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
				float3 worldNormal = normalize(mul(objectToWorld, currentvertex.normalOS));
								
				float3 rayOrigin = WorldRayOrigin();
				float3 rayDir = WorldRayDirection();
				// get intersection world position
				float3 worldPos = rayOrigin + RayTCurrent() * rayDir;

				// get random vector
				float3 randomVector;int i=0;
				do {
					randomVector = float3(nextRand(rayPayload.randomSeed),nextRand(rayPayload.randomSeed),nextRand(rayPayload.randomSeed)) * 2-1;
				} while(i++ < 10 && dot(randomVector,randomVector) > 1.0);

				// get random scattered ray dir along surface normal				
				float3 scatterRayDir = normalize(worldNormal + randomVector);
				float3 _Color = worldNormal * 0.5 + 0.5;

				rayPayload.pos = worldPos;
				rayPayload.dir = scatterRayDir;

				if(rayPayload.depth > 0){
					rayPayload.color *= _Color;
				}

				// define GPT material parameters

				// microfacet distribution; visible = true (distr of visible normals)
				// there are multiple types... which one do we choose? Beckmann, GGX, Phong
				// alphaU, alphaV = roughnesses in tangent and bitangent direction
				// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/microfacet.h

				// define geoFrame and shFrame;
				// the function is defined to make y = up, but for Mitsuba, we need z = up, so we swizzle it
				rayPayload.geoFrame = normalToFrame(worldNormal);
				rayPayload.shFrame = rayPayload.geoFrame;

				rayPayload.bsdf.roughness = 1.0;
				rayPayload.bsdf.color = _Color;

				// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/roughdiffuse.cpp
				rayPayload.bsdf.components[0].type = EGlossyReflection;
				rayPayload.bsdf.components[0].roughness = Infinity;// why?
				rayPayload.bsdf.numComponents = 1;
				rayPayload.bsdf.materialType = DIFFUSE;
				
			}			

			ENDHLSL
		}
	}
}
