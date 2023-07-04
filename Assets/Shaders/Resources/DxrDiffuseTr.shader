Shader "RayTracing/DxrDiffuseTr" {
	Properties {
		_Color ("Color", Color) = (1, 1, 1, 1)
		_MainTex ("Albedo", 2D) = "white" { }
		_Metallic ("Metallic (white)", Range(0, 1)) = 0.0
		_Metallic2 ("Metallic (black)", Range(0, 1)) = 0.0
		_MetallicGlossMap ("Metallic Mask", 2D) = "white" {}
		_Glossiness ("Smoothness (white)", Range(0, 1)) = 0.5
		_Glossiness2 ("Smoothness (black)", Range(0, 1)) = 0.0
		_SpecGlossMap ("Smoothness Mask", 2D) = "white" {}
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
			float2 uv_MetallicGlossMap;
			float2 uv_BumpMap;
		};
        	
		float4 _Color;
		float _Metallic, _Glossiness;
		float _Metallic2, _Glossiness2;
		sampler2D _MainTex, _MetallicGlossMap;
		sampler2D _BumpMap;

		void surf(Input IN, inout SurfaceOutputStandard o) {
			fixed4 c = tex2D(_MainTex, IN.uv_MainTex) * _Color;
			if(c.a < 0.005) discard;
			o.Albedo = c.rgb;
			o.Metallic = lerp(_Metallic2, _Metallic, tex2D(_MetallicGlossMap, IN.uv_MetallicGlossMap).x);
			o.Smoothness = 1.0;// needs to be high, so the surfels are regularly updated
			o.Normal = UnpackNormal (tex2D (_BumpMap, IN.uv_BumpMap));
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

			float4 _Color;
			Texture2D _MainTex;
			float4 _MainTex_ST;
			SamplerState sampler_MainTex;

			#define GetColor() _MainTex.SampleLevel(sampler_MainTex, TRANSFORM_TEX(vertex.texCoord0, _MainTex), lod) * _Color

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
