Shader "RayTracing/Accu" {
	Properties {
		[Toggle(USE_MOTION_VECTORS)]
        _UseMotionVectors ("Use Motion Vectors", Float) = 0.0
	}
	SubShader {

		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass {
			CGPROGRAM

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"
			#include "UnityStandardUtils.cginc"
			#include "SimpleCopy.cginc"

			// built-in motion vectors
			sampler2D_half _CameraMotionVectorsTexture;

			sampler2D _CurrentFrame;
			sampler2D _Accumulation;
			int _FrameIndex;
			float _Discard;
			float _UseMotionVectors;

			float3 _DeltaCameraPosition;

			// GBuffer for metallic & roughness
			sampler2D _CameraGBufferTexture0;
			sampler2D _CameraGBufferTexture1;
			sampler2D _CameraGBufferTexture2;
			sampler2D _CameraDepthTexture;

			// previous frame GBuffers
			sampler2D prevGBuff0;
			sampler2D prevGBuff1;
			sampler2D prevGBuff2;
			sampler2D prevGBuffD;

			// current GBuffer data
			void GetGBuffer0(float2 uv, out half specular, out half depth, out half3 color, out half3 spec){
				half4 gbuffer0 = tex2D(_CameraGBufferTexture0, uv);
				half4 gbuffer1 = tex2D(_CameraGBufferTexture1, uv);
				half4 gbuffer2 = tex2D(_CameraGBufferTexture2, uv);
				UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
				specular = SpecularStrength(data.specularColor);
				depth = Linear01Depth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
				color = data.diffuseColor;
				spec = data.specularColor;
			}

			// previous GBuffer data
			void GetGBuffer1(float2 uv, out half specular, out half depth, out half3 color, out half3 spec){
				half4 gbuffer0 = tex2D(prevGBuff0, uv);
				half4 gbuffer1 = tex2D(prevGBuff1, uv);
				half4 gbuffer2 = tex2D(prevGBuff2, uv);
				UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
				specular = SpecularStrength(data.specularColor);
				depth = Linear01Depth(SAMPLE_DEPTH_TEXTURE(prevGBuffD, uv));
				color = data.diffuseColor;
				spec = data.specularColor;
			}

			float4 _CameraDepthTexture_TexelSize;

			float4 frag (v2f i) : SV_Target {

				float2 uv = i.uv;

				if(_Discard) return tex2D(_CurrentFrame, uv);
				else if(_UseMotionVectors > 0.5) {

					float4 currentFrame = tex2D(_CurrentFrame, uv);

					float2 motion = tex2D(_CameraMotionVectorsTexture, uv);
					float2 uv2 = uv - motion;

					// to do this needs a depth-difference check as well
					// it would help to have a z component for motion vectors...
					// -> we might need our own motion vector pass :)

					if(uv2.x > 0.0 && uv2.y > 0.0 && uv2.x < 1.0 && uv2.y < 1.0){

						half spec0, spec1, depth0, depth1;
						half3 col0, col1, emm0, emm1;
						GetGBuffer0(uv,spec0,depth0,col0,emm0);
						if(depth0 >= 1.0) return float4(0,0,0,1);
						
						
						float4 previousFrame = tex2D(_Accumulation, uv2);
						GetGBuffer1(uv2,spec1,depth1,col1,emm1);
						// half3 colorDifference = col1 - col0;
						half3 specDifference = emm1 - emm0;
						float dd = abs(log2(depth0/depth1));
						float prevWeight = saturate(1.0 - 10.0 * abs(spec0-spec1)) * 
							// saturate(1.0 - 10.0 * dot(colorDifference, colorDifference)) *
							// remove confidence in reflective surfaces, when the angle (~ camera position) changes
							saturate(1.0 - 10.0 * max(spec0,spec1) * length(_DeltaCameraPosition)) * // to do depends on angle, not really on distance...
							// saturate(1.0 - 10.0 * dot(specDifference, specDifference));// *
							saturate(1.0 - dd);

						// compute linear average of all rendered frames
						return float4(currentFrame.rgb + previousFrame.rgb * prevWeight, currentFrame.a + prevWeight * previousFrame.a);
					} else return currentFrame;

				} else {

					float4 currentFrame = tex2D(_CurrentFrame, uv);
					float4 previousFrame = tex2D(_Accumulation, uv);

					// compute linear average of all rendered frames
					float blendFactor = 1.0 / float(_FrameIndex + 1);
					return lerp(previousFrame, currentFrame, blendFactor);

				}
			}
			ENDCG
		}
	}
}
