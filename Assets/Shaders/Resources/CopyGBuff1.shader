Shader "RayTracing/CopyGBuff1" {
	Properties {}
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass {
			CGPROGRAM

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"
			#include "SimpleCopy.cginc"

			sampler2D _CameraGBufferTexture1;

			float4 frag (v2f i) : SV_Target {
				return tex2D(_CameraGBufferTexture1, i.uv);
			}

			ENDCG
		}
	}
}
