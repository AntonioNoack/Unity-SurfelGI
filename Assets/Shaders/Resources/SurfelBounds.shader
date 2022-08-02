Shader "RayTracing/SurfelBounds" {
	Properties { }
	SubShader {
		
		Tags { "RenderType" = "Transparent" }
		LOD 100

		// basic pass for GBuffer
		CGPROGRAM
		#pragma surface surf Standard fullforwardshadows

		UNITY_INSTANCING_BUFFER_START(Props)
        UNITY_INSTANCING_BUFFER_END(Props)

		struct Input {
			float2 uv_MainTex;
		};

		void surf(Input input, inout SurfaceOutputStandard o) {
			o.Albedo = 1;
			o.Metallic = 0;
			o.Smoothness = 0;
			o.Alpha = 1;
		}
		ENDCG

		// reverse ray tracing: light -> surfels
		Pass {
			Name "DxrPass2"
			Tags { "LightMode" = "DxrPass2" }

			HLSLPROGRAM

			#pragma raytracing test
			
			#include "Common.cginc"
			#include "Surfel.cginc"

			RWStructuredBuffer<Surfel> _Surfels;

			[shader("closesthit")]
			void ClosestHit(inout LightIntoSurfelPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				// the closest surfel is nothing special
			}

			[shader("anyhit")]
			void AnyHitMain(inout LightIntoSurfelPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {

				// get surfel id
				// todo if close enough, add value to surfel

				uint surfelId = PrimitiveIndex();
				uint length1, stride;
				_Surfels.GetDimensions(length1, stride);
				if(surfelId < length1) {
					Surfel surfel = _Surfels[surfelId];
					float3 pos = surfel.position.xyz;
					float size = surfel.position.w;

					// calculate distance
					float3 rayPos = WorldRayOrigin(), rayDir = WorldRayDirection();
					float3 pa = pos - rayPos;
					float3 cl = pa - rayDir * dot(rayDir, pa);
					float distanceSq = dot(cl, cl);

					// todo calculate alignment

					if(distanceSq < size * size) {
						surfel.color += rayPayload.color;
						_Surfels[surfelId] = surfel;
					}

 				}

				IgnoreHit(); // we want to hit all surfels :D
			}

			ENDHLSL
		}
	}
}
