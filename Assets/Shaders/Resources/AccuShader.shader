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

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"
			#include "UnityStandardUtils.cginc"
			#include "SimpleCopy.cginc"

			// built-in motion vectors
			sampler2D_half _CameraMotionVectorsTexture;

			sampler2D _CurrentFrame;
			sampler2D _Accumulation;
			int _FrameIndex;
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

				if(_UseMotionVectors > 0.5){

					float4 currentFrame = tex2D(_CurrentFrame, uv);
					currentFrame.w = 1.0;

					float2 motion = tex2D(_CameraMotionVectorsTexture, uv);
					float2 uv2 = uv - motion;

					// todo this needs a depth-difference check as well
					// todo it would help to have a z component for motion vectors...
					// todo -> we might need our own motion vector pass :)

					// this is incorrect, but often works;
					// but because it's incorrect, sometimes that shows...
					// float4 accumulation = tex2D(_Accumulation, uv);
					// accumulation.w *= 0.25;

					float4 accumulation = float4(0,0,0,0);

					float blendFactor = 1.0;
					if(uv2.x > 0.0 && uv2.y > 0.0 && uv2.x < 1.0 && uv2.y < 1.0){

						half spec0, spec1, depth0, depth1;
						half3 col0, col1, emm0, emm1;
						GetGBuffer0(uv,spec0,depth0,col0,emm0);
						
						// nice try, but not really working
						/*float4 texSize = _CameraDepthTexture_TexelSize; // (1/wh,wh)
						float2 uv2i = uv2 * texSize.zw;
						// check depth of [0,1] + uv2
						float2 f = frac(uv2i) * texSize.xy, g = 1.0 - f;
						int valid = 0;
						for(int y=0;y<=1;y++){
							for(int x=0;x<=1;x++){
								float2 uv3 = uv - f + (float2(x,y) + 0.5) * texSize.xy;
								float d0 = depth0, d1 = Linear01Depth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv3));
								bool close = abs(d0-d1) < max(abs(d0),abs(d1)) * 0.2;
								valid |= (close ? 1 : 0) << (x + (y << 1));
							}
						}

						if(valid == 0){
							blendFactor = 1.0;
						} else {
							if(valid != 0 && valid != 15){
								if(valid & 5 < 5) uv2.x -= f.x - 0.5;
								else if(valid & 10 < 10) uv2.x += g.x + 0.5;
								if(valid & 3 < 3) uv2.y -= f.y - 0.5;
								else if(valid & 12 < 12) uv2.y += g.y + 0.5;
							}*/

							accumulation = tex2D(_Accumulation, uv2);
							GetGBuffer1(uv2,spec1,depth1,col1,emm1);
							half3 colorDifference = col1 - col0;
							half3 specDifference = emm1 - emm0;
							accumulation.w *= saturate(1.0 - 10.0 * abs(spec0-spec1)) * 
								// saturate(1.0 - 10.0 * dot(colorDifference, colorDifference)) *
								// remove confidence in reflective surfaces, when the angle (~ camera position) changes
								saturate(1.0 - 10.0 * max(spec0,spec1) * length(_DeltaCameraPosition)) * // to do depends on angle, not really on distance...
								// saturate(1.0 - 10.0 * dot(specDifference, specDifference));// *
								saturate(1.0 - 1.0 * abs(log2(depth0/depth1)));
							blendFactor = 1.0 / (accumulation.w + 1.0);
						//}
					}

					// compute linear average of all rendered frames
					return float4(
						lerp(accumulation, currentFrame, blendFactor).rgb,
						accumulation.w + 1.0
					);

				} else {

					float4 currentFrame = tex2D(_CurrentFrame, uv);
					float4 accumulation = tex2D(_Accumulation, uv);

					// compute linear average of all rendered frames
					float blendFactor = 1.0 / float(_FrameIndex + 1);
					return lerp(accumulation, currentFrame, blendFactor);

				}
			}
			ENDCG
		}
	}
}
