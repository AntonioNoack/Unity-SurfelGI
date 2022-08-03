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
			Tags { "LightMode" = "DxrPass" }

			HLSLPROGRAM

			#pragma raytracing test
			
			#include "Common.cginc"
			#include "Surfel.cginc"

			StructuredBuffer<Surfel> _Surfels;

			[shader("closesthit")]
			void SurfelBoundsClosest(inout LightIntoSurfelPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				// the closest surfel is nothing special 

				uint surfelId = PrimitiveIndex();
				uint length1, stride;
				_Surfels.GetDimensions(length1, stride);
				if(surfelId < length1) {
					Surfel surfel = _Surfels[surfelId];
					float3 pos = surfel.position.xyz;
					float size = surfel.position.w;

					// calculate distance
					float3 dp = WorldRayOrigin() - pos;
					float distanceSq = dot(dp,dp);

					// todo calculate alignment

					if(/*distanceSq < size * size &&*/ rayPayload.hitIndex < 16) {
						// surfel.color += rayPayload.color;
						// _Surfels[surfelId] = surfel; // unfortunately not supported :/
						rayPayload.hits[rayPayload.hitIndex++] = surfelId;
					}
				}

			}

			/*[shader("anyhit")]
			void SurfelBoundsAny(inout LightIntoSurfelPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {

				// get surfel id
				// if close enough, add value to surfel

				uint surfelId = PrimitiveIndex();
				uint length1, stride;
				_Surfels.GetDimensions(length1, stride);
				if(surfelId < length1) {
					Surfel surfel = _Surfels[surfelId];
					float3 pos = surfel.position.xyz;
					float size = surfel.position.w;

					// calculate distance
					float3 dp = WorldRayOrigin() - pos;
					float distanceSq = dot(dp,dp);

					// todo calculate alignment

					// if(distanceSq < size * size && rayPayload.hitIndex < 16) {
					if(rayPayload.hitIndex < 16) {
						// surfel.color += rayPayload.color;
						// _Surfels[surfelId] = surfel; // unfortunately not supported :/
						rayPayload.hits[rayPayload.hitIndex++] = surfelId;
					}

 				}
				
				IgnoreHit(); // we want to hit all surfels :D

			}*/

			ENDHLSL
		}
	}
}
