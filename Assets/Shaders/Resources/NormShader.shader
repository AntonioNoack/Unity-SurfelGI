﻿Shader "RayTracing/NormShader" {
	Properties {
		_MainTex ("Albedo", 2D) = "white" { }
	}
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always
		Pass {
			CGPROGRAM

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"
			#include "SimpleCopy.cginc"

			sampler2D _MainTex;

			float4 frag (v2f i) : SV_Target {
				float4 color = tex2D(_MainTex, i.uv);
				return float4(color.xyz/max(color.w, 0.0001), 1.0);
			}

			ENDCG
		}
	}
}
