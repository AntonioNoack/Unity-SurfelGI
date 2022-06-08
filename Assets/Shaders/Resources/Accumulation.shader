Shader "RayTracing/Accumulation" {
	Properties {
		[Toggle(USE_MOTION_VECTORS)]
        _UseMotionVectors ("Use Motion Vectors", Float) = 0.0
	}
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass {
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#include "UnityCG.cginc"

			struct appdata {
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
			};

			struct v2f {
				float2 uv : TEXCOORD0;
				float4 vertex : SV_POSITION;
			};

			v2f vert (appdata v) {
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}

			// built-in motion vectors
			sampler2D_half _CameraMotionVectorsTexture;

			sampler2D _CurrentFrame;
			sampler2D _Accumulation;
			int _FrameIndex;
			float _UseMotionVectors;

			float4 frag (v2f i) : SV_Target {

				float4 currentFrame = tex2D(_CurrentFrame, i.uv);
				currentFrame.w = 1.0;

				float2 motion = tex2D(_CameraMotionVectorsTexture, i.uv);
				float2 uv2 = i.uv - motion;

				// todo this needs a depth-difference check as well
				// todo plus a reflectivity check
				bool inside = uv2.x > 0.0 && uv2.y > 0.0 && uv2.x < 1.0 && uv2.y < 1.0;
				float4 accumulation = 
					inside ?
					tex2D(_Accumulation, uv2) : float4(0,0,0,0);

				// compute linear average of all rendered frames
				float blendFactor = _UseMotionVectors > 0.5 ?
					1.0 / (accumulation.w + 1.0) :
					1.0 / float(_FrameIndex + 1);
			
				return float4(
					lerp(accumulation, currentFrame, blendFactor).rgb,
					accumulation.w + 1.0
				);
			}
			ENDCG
		}
	}
}
