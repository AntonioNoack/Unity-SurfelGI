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
			o.Albedo = float3(1.0,1.0,1.0);
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
					   
			#include "Common.cginc"

			float4 _Color;

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {	
				// emissive material, simply return emission color
				rayPayload.distance = RayTCurrent();
				rayPayload.color = _Color.xyz;		
			}			

			ENDHLSL
		}
	}
}
