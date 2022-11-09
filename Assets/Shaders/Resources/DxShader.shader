Shader "RayTracing/GradientShader" {
	Properties { }
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always
		Pass {
			CGPROGRAM

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"
			#include "SimpleCopy.cginc"

			sampler2D _Src;
			float2 _DeltaUV;

			float4 frag (v2f i) : SV_Target {
				float4 c0 = tex2D(_Src, i.uv + _DeltaUV);
				float4 c1 = tex2D(_Src, i.uv - _DeltaUV);
				return float4((c0.rgb/(c0.w+0.0001) - c1.rgb/(c1.w+0.0001)) * 0.5, 1.0);
			}

			ENDCG
		}
	}
}
