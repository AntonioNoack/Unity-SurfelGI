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
			float _Complex;

			float4 frag (v2f i) : SV_Target {
				float minValue = 0.00001;
				if(_Complex){
					float4 c = tex2D(_RGBTex, i.uv);
					float4 dc = tex2D(_WTex, i.uv);
					return float4((dc.rgb*c.w-c.rgb*dc.w)/(c.w*c.w+minValue), 1.0);
				} else {
					float3 color = tex2D(_RGBTex, i.uv).rgb;
					float weight = tex2D(_WTex, i.uv).w;
					return float4((color.xyz+minValue*_Default)/(weight+minValue), 1.0);
				}
			}

			ENDCG
		}
	}
}
