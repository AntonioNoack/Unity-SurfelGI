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
				return (tex2D(_Src, i.uv + _DeltaUV) - tex2D(_Src, i.uv - _DeltaUV));
			}

			ENDCG
		}
	}
}
