Shader "RayTracing/PoissonShader" {
	Properties { }
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always
		Pass {
			CGPROGRAM

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"
			#include "SimpleCopy.cginc"

			Texture2D _Src;
			Texture2D _Dx;
			Texture2D _Dy;
			Texture2D _Blurred;
			SamplerState src_point_clamp_sampler;

			float2 _Dx2, _Dy2, _Dx1, _Dy1;

			float4 frag (v2f i) : SV_Target {
				// float4 a0 = tex2D(_Src, i.uv);
				float4 a1 = _Src.Sample(src_point_clamp_sampler, i.uv-_Dx2);
				float4 a2 = _Src.Sample(src_point_clamp_sampler, i.uv-_Dy2);
				float4 a3 = _Src.Sample(src_point_clamp_sampler, i.uv+_Dx2);
				float4 a4 = _Src.Sample(src_point_clamp_sampler, i.uv+_Dy2);
				float4 dxp = _Dx.Sample(src_point_clamp_sampler, i.uv+_Dx1);
				float4 dyp = _Dy.Sample(src_point_clamp_sampler, i.uv+_Dy1);
				float4 dxm = _Dx.Sample(src_point_clamp_sampler, i.uv-_Dx1);
				float4 dym = _Dy.Sample(src_point_clamp_sampler, i.uv-_Dy1);
				// 2.0 works well for pixels; for surfels, everything seems to be broken :/ ...
				float4 t0 = ((a1+a2+a3+a4) + 2.0*((dxm-dxp) + (dym-dyp))) * 0.25;
				// float4 t1 = tex2D(_Blurred, i.uv);
				// return lerp(a0, lerp(t0, t1, 0.05), 0.75);
				return max(t0, float4(0,0,0,0));
			}

			ENDCG
		}
	}
}
