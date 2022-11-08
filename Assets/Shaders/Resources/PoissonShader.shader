Shader "RayTracing/PoissonShader" {
	Properties {}
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always
		Pass {
			CGPROGRAM

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"
			#include "SimpleCopy.cginc"

			sampler2D _Src;
			sampler2D _Dx;
			sampler2D _Dy;
			sampler2D _Blurred;

			float2 _Dx2, _Dy2, _Dx1, _Dy1;

			float4 frag (v2f i) : SV_Target {
				// float4 a0 = tex2D(_Src, i.uv);
				float4 a1 = tex2D(_Src, i.uv-_Dx2);
				float4 a2 = tex2D(_Src, i.uv-_Dy2);
				float4 a3 = tex2D(_Src, i.uv+_Dx2);
				float4 a4 = tex2D(_Src, i.uv+_Dy2);
				float4 dxp = tex2D(_Dx, i.uv+_Dx1);
				float4 dyp = tex2D(_Dy, i.uv+_Dy1);
				float4 dxm = tex2D(_Dx, i.uv-_Dx1);
				float4 dym = tex2D(_Dy, i.uv-_Dy1);
				float4 t0 = ((a1+a2+a3+a4) + ((dxm-dxp) + (dym-dyp))) * 0.25;
				// float4 t1 = tex2D(_Blurred, i.uv);
				// return lerp(a0, lerp(t0, t1, 0.05), 0.75);
				return t0;
			}

			ENDCG
		}
	}
}
