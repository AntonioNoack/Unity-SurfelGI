Shader "RayTracing/Add" {
	Properties { }
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always
		Pass {
			CGPROGRAM

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"
			#include "SimpleCopy.cginc"

			Texture2D _TexA;
			Texture2D _TexB;
			Texture2D _TexC;
			SamplerState src_point_clamp_sampler;

			float4 frag (v2f i) : SV_Target {
				return _TexA.Sample(src_point_clamp_sampler, i.uv) +
					_TexB.Sample(src_point_clamp_sampler, i.uv) +
					_TexC.Sample(src_point_clamp_sampler, i.uv);
			}

			ENDCG
		}
	}
}
