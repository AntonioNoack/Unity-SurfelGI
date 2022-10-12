Shader "RayTracing/DxrDiffuseNormal" {
	Properties {
		_Metallic ("Metallic", Range(0, 1)) = 0.0
		_Glossiness ("Smoothness", Range(0, 1)) = 0.5
		// [Normal] _DetailNormalMap ("Normal Map", 2D) = "bump" {}
		_DetailNormalMapScale("Scale", Float) = 1.0
		// [Normal] _BumpMap("Normal Map", 2D) = "bump" {}
		_BumpMap("Normal Map", 2D) = "bump" {}
	}
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
			
		float _Metallic;
		float _Glossiness;

		void surf(Input input, inout SurfaceOutputStandard o) {
			o.Albedo = input.worldNormal * 0.5 + 0.5;
			o.Metallic = _Metallic;
			o.Smoothness = _Glossiness;
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

			#define GetColor() float4(worldNormal * 0.5 + 0.5, 1.0)
			#include "DXRDiffuse.cginc"		

			ENDHLSL
		}
	}
}
