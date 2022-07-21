Shader "RayTracing/BlurShader" {
	Properties {}
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always
		Pass {
			CGPROGRAM

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"
			#include "SimpleCopy.cginc"

			sampler2D _MainTex; // set in Graphics.Blit(src,dst,material) command for src
			float2 _DeltaUV;
			float _Weights[255]; // assumed maximum needed length; Unitys internal maximum is 1023
			int _N;

			float4 frag (v2f i) : SV_Target {
				float4 sum = 0;
				int n = min(_N, 127);
				for(int j=-n;j<=n;j++){
					sum += -_Weights[j + _N] * tex2D(_MainTex, i.uv + _DeltaUV * j);
				}
				return sum;
			}

			ENDCG
		}
	}
}
