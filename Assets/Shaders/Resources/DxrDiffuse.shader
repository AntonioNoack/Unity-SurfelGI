Shader "RayTracing/DxrDiffuse" {
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
			float2 uv_MetallicGlossMap;
			float2 uv_SpecGlossMap;
			float2 uv_BumpMap;
		};
        
		float4 _Color;
		float _Metallic, _Glossiness;
		float _Metallic2, _Glossiness2;
		sampler2D _MainTex;
		sampler2D _MetallicGlossMap;
		sampler2D _SpecGlossMap;
		sampler2D _BumpMap;

		void surf(Input IN, inout SurfaceOutputStandard o) {
			o.Albedo = (tex2D(_MainTex, IN.uv_MainTex) * _Color).xyz;
			o.Metallic = lerp(_Metallic2, _Metallic, tex2D(_MetallicGlossMap, IN.uv_MetallicGlossMap).x);
			o.Smoothness = lerp(_Glossiness2, _Glossiness, tex2D(_SpecGlossMap, IN.uv_SpecGlossMap).x);
			o.Normal = UnpackNormal(tex2D(_BumpMap, IN.uv_BumpMap));
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

			// the naming comes from Unitys default shader

			float4 _Color;
			Texture2D _MainTex;
			float4 _MainTex_ST;
			SamplerState sampler_MainTex;

			#define GetColor() _MainTex.SampleLevel(sampler_MainTex, TRANSFORM_TEX(vertex.texCoord0, _MainTex), lod) * _Color
			// #define GetColor() float4(frac(TRANSFORM_TEX(vertex.texCoord0, _MetallicGlossMap)), 0.0, 1.0)

			#include "DXRDiffuse.cginc"

			ENDHLSL
		}
	}
}
