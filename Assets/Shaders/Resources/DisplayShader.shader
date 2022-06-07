Shader "Hidden/Display" {
	Properties {
		_Exposure("Exposure", Range(0.0, 1000.0)) = 1.0
	}
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass {
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#include "UnityCG.cginc"
			// for reading the GBuffer
			#include "UnityGBuffer.cginc"

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

			float _Exposure;

			// Unitys predefined GBuffer data
			sampler2D _CameraGBufferTexture0;
			sampler2D _CameraGBufferTexture1;
			sampler2D _CameraGBufferTexture2;

			sampler2D _Accumulation;

			void readSurfaceInfo(float2 uv, out float3 color, out float3 normal){
				half4 gbuffer0 = tex2D(_CameraGBufferTexture0, uv);
				half4 gbuffer1 = tex2D(_CameraGBufferTexture1, uv);
				half4 gbuffer2 = tex2D(_CameraGBufferTexture2, uv);
				UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
				color = data.diffuseColor + data.specularColor;
				normal = data.normalWorld;
			}

			float3 HDR_to_LDR(float3 hdr){
				hdr *= _Exposure;
				return hdr/(hdr+1.0);
			}

			float4 frag (v2f i) : SV_Target {
				float2 uv = i.uv;
				float2 duv = float2(ddx(uv.x), ddy(uv.y));

				// from https://github.com/TwoTailsGames/Unity-Built-in-Shaders/blob/master/DefaultResourcesExtra/Internal-DeferredReflections.shader
				float3 color, normal;
				readSurfaceInfo(uv, color, normal);
				float3 color0 = color;
				
				// gaussian blur as a first test
				float4 sum = float4(0.0,0.0,0.0,0.0);
				float numSigmas = 2.5;
				int di = 5;
				float sigma = numSigmas / float(di*di);
				for(int j=-di;j<=di;j++){
					for(int i=-di;i<=di;i++){
						float2 uv2 = uv + float2(i,j) * duv;
						float3 nor, _col;
						readSurfaceInfo(uv2, _col, nor);
						float3 illumination = tex2D(_Accumulation, uv2).rgb;
						float weight = i == 0 && j == 0 ? 1.0 : exp(-sigma*float(i*i+j*j)) * max(0.0, dot(nor,normal) - 0.8);
						sum += float4(illumination.xyz * weight, weight);
					}
				}
				color *= sum.xyz * (_Exposure / sum.w);
				color = HDR_to_LDR(color);
				return float4(color, 1.0);
				
				// return float4(uv.y < 0.5 ? HDR_to_LDR(tex2D(_Accumulation, uv).rgb) : color0, 1.0);
				// return float4(normalize(normal)*.5+.5, 1.0);
			}
			ENDCG
		}
	}
}
