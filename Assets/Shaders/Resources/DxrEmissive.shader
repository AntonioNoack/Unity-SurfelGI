Shader "RayTracing/DxrEmissive" {
	Properties {
		[HDR] _Color ("Color", Color) = (1, 1, 1, 1)
		_MainTex ("Albedo", 2D) = "white" { }
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
        
		float4 _Color;
		sampler2D _MainTex;
        
		void surf(Input IN, inout SurfaceOutputStandard o) {
			o.Albedo = 1.0;//(tex2D(_MainTex, IN.uv_MainTex) * _Color).xyz;
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
			Texture2D _MainTex;
			SamplerState sampler_MainTex;

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				
				// emissive material, simply return emission color
				rayPayload.distance = RayTCurrent();

				IntersectionVertex vertex;
				GetCurrentIntersectionVertex(attributeData, vertex);

				float lod = 0;
				float4 color = _MainTex.SampleLevel(sampler_MainTex, vertex.texCoord0, lod) * _Color;
				rayPayload.color *= color.xyz * color.w;
				rayPayload.dir = float3(0,0,0);

			}

			ENDHLSL
		}
	}
}
