Shader "RayTracing/AddShader" {
	Properties {}
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always
		Pass {
			CGPROGRAM

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"
			#include "SimpleCopy.cginc"

			sampler2D _TexA;
			sampler2D _TexB;
			sampler2D _TexC;

			float4 frag (v2f i) : SV_Target {
				return tex2D(_TexA, i.uv) + tex2D(_TexB, i.uv) + tex2D(_TexC, i.uv);
			}

			ENDCG
		}
	}
}
