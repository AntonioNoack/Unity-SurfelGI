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

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				// the closest surfel is nothing special
			}

			[shader("anyhit")]
			void AnyHitMain(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {

				// todo get surfel id
				// todo calculate distance (and alignment?)
				// todo if close enough, add value to surfel

				

				IgnoreHit(); // we want to hit all surfels :D
			}

			ENDHLSL
		}
	}
}
