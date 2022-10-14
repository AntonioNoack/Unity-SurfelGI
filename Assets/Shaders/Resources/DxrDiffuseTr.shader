Shader "RayTracing/DxrDiffuseTr" {
	Properties {
		_Color ("Color", Color) = (1, 1, 1, 1)
		_MainTex ("Albedo", 2D) = "white" { }
		_Metallic ("Metallic", Range(0, 1)) = 0.0
		_Glossiness ("Smoothness", Range(0, 1)) = 0.5
		// [Normal] _DetailNormalMap ("Normal Map", 2D) = "bump" {}
		_DetailNormalMapScale("Scale", Float) = 1.0
		// [Normal] _BumpMap("Normal Map", 2D) = "bump" {}
		_BumpMap("Normal Map", 2D) = "bump" {}
		_IsTrMarker("IsTrMarker(ignored)", Range(0.0, 0.1)) = 0.0
	}
	SubShader {
		// if the material is fully opaque, you can set it to Opaque, otherwise use Transparent.
		// using opaque will ignore the anyhit shader
		Tags { "RenderType" = "Transparent" }
		// Tags { "RenderType" = "Opaque" }
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
		float _Metallic, _Glossiness;
		sampler2D _MainTex;

		void surf(Input IN, inout SurfaceOutputStandard o) {
			fixed4 c = tex2D(_MainTex, IN.uv_MainTex) * _Color;
			if(c.a < 0.5) discard;
			o.Albedo = c.rgb;
			o.Metallic = 1.0;
			o.Smoothness = 1.0;// needs to be high, so the surfels are regularly updated
			o.Alpha = c.a;
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

			float4 _Color;
			Texture2D _MainTex;
			SamplerState sampler_MainTex;

			#define GetColor() _MainTex.SampleLevel(sampler_MainTex, vertex.texCoord0, lod) * _Color
			#include "DXRDiffuse.cginc"

			[shader("anyhit")]
			void AnyHitMain(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				IntersectionVertex vertex;
				GetCurrentIntersectionVertex(attributeData, vertex);
				float alpha = _MainTex.SampleLevel(sampler_MainTex, vertex.texCoord0, 0).a * _Color.a;
				if(alpha < nextRand(rayPayload.randomSeed)) {
					IgnoreHit();
				}
				
				// another possibility:
				// AcceptHitAndEndSearch();
				
			}

			ENDHLSL
		}
	}
}
