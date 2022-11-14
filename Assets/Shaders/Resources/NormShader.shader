Shader "RayTracing/NormShader" {
	Properties { }
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always
		Pass {
			CGPROGRAM

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"
			#include "SimpleCopy.cginc"

			sampler2D _RGBTex;
			sampler2D _WTex;
			float _Default;

			float4 frag (v2f i) : SV_Target {
				float3 color = tex2D(_RGBTex, i.uv).rgb;
				float weight = tex2D(_WTex, i.uv).w;
				float minValue = 0.00001;
				return float4((color.xyz+minValue*_Default)/(weight+minValue), 1.0);
			}

			ENDCG
		}
	}
}
