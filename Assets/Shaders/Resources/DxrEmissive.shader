Shader "RayTracing/DxrEmissive" {
	Properties {
		[HDR] _Color ("Color", Color) = (1, 1, 1, 1)
	}
	SubShader {
		Tags { "RenderType"="Opaque" }
		LOD 100

		// basic pass for GBuffer
		CGPROGRAM
		#pragma surface surf Standard fullforwardshadows

		UNITY_INSTANCING_BUFFER_START(Props)
        UNITY_INSTANCING_BUFFER_END(Props)

		struct Input {
			float2 uv_MainTex;
		};
        
		void surf(Input IN, inout SurfaceOutputStandard o) {
			o.Albedo = float3(1,1,1);
			o.Metallic = 0.0;
			o.Smoothness = 0.0;
			o.Alpha = 1.0;
		}
		ENDCG

		// surfel -> light pass; emissive, so the end
		Pass {
			Name "DxrPass"
			Tags { "LightMode" = "DxrPass" }

			HLSLPROGRAM

			#pragma raytracing test
					   
			#include "RTLib.cginc"

			float4 _Color;

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {	
				// emissive material, simply return emission color
				rayPayload.distance = RayTCurrent();
				rayPayload.color *= _Color.xyz;
				rayPayload.dir = 0;
			}

			ENDHLSL
		}

		// light -> surfel pass; emissive, so the start a.k.a. cannot be used as reflective surface
		Pass {
			Name "DxrPass2"
			Tags { "LightMode" = "DxrPass2" }

			HLSLPROGRAM

			#pragma raytracing test
					   
			#include "RTLib.cginc"

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {	
				rayPayload.color = 0;
			}

			ENDHLSL
		}
	}
}
