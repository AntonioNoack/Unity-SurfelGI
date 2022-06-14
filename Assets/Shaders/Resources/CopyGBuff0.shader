Shader "RayTracing/CopyGBuff0" {
	Properties {}
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass {
			CGPROGRAM

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"
			#include "SimpleCopy.cginc"

			sampler2D _CameraGBufferTexture0;

			float4 frag (v2f i) : SV_Target {
				return tex2D(_CameraGBufferTexture0, i.uv);
			}

			ENDCG
		}
	}
}
