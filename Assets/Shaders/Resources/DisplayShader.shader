Shader "RayTracing/Display" {
	Properties {
		_Exposure("Exposure", Range(0.0, 1000.0)) = 1.0
		_SplitX("SplitX", Range(0,1)) = 0.75
		_SplitY("SplitY", Range(0,1)) = 0.50
	}
	SubShader {
		// No culling or depth
		Cull Off ZWrite Off ZTest Always

		Pass {
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#include "UnityCG.cginc"
			#include "UnityGBuffer.cginc"

			struct appdata {
				float4 vertex : POSITION;
				float2 uv : TEXCOORD0;
				float4 tangent: TANGENT;
				float3 normal: NORMAL;
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
			float _SplitX, _SplitY;
			float _Far;

			float2 _CameraScale;
			float4 _CameraRotation;

			// Unitys predefined GBuffer data
			sampler2D _CameraGBufferTexture0;
			sampler2D _CameraGBufferTexture1;
			sampler2D _CameraGBufferTexture2;
			sampler2D _CameraDepthTexture;
			samplerCUBE _SkyBox;
			// sampler2D_half _CameraMotionVectorsTexture;

			sampler2D _Accumulation;

			float3 quatRot(float3 v, float4 q){
				return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
			}

			void readSurfaceInfo(float2 uv, float3 dir, out float3 color, out float3 normal){
				half4 gbuffer0 = tex2D(_CameraGBufferTexture0, uv);
				half4 gbuffer1 = tex2D(_CameraGBufferTexture1, uv);
				half4 gbuffer2 = tex2D(_CameraGBufferTexture2, uv);
				UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
				color = data.diffuseColor + data.specularColor;
				normal = data.normalWorld;
				float depth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
				if(dot(color,color) < 0.01 && depth >= _Far * 0.99){
					color = texCUBE(_SkyBox, dir);
					// color = normalize(dir)*.5+.5;
				}
				// float4 viewPos = float4(i.ray * depth, 1);
				// float3 worldPos = mul(unity_CameraToWorld, viewPos).xyz;
			}

			float3 readSurfaceNormal(float2 uv){
				half4 gbuffer0 = tex2D(_CameraGBufferTexture0, uv);
				half4 gbuffer1 = tex2D(_CameraGBufferTexture1, uv);
				half4 gbuffer2 = tex2D(_CameraGBufferTexture2, uv);
				UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
				return data.normalWorld;
			}

			float3 HDR_to_LDR(float3 hdr){
				// hdr *= _Exposure;
				return hdr/(hdr+1.0);
			}

			float4 frag (v2f i) : SV_Target {

				float4 ill = tex2D(_Accumulation, i.uv);
				/*if(i.uv.x < 0.5)*/ return float4((ill.xyz/max(1.0,ill.w)), 1.0);

				float2 uv = i.uv;
				float3 rayDir = normalize(quatRot(float3((uv - 0.5) * _CameraScale.xy, 1.0), _CameraRotation));
				float2 duv = float2(ddx(uv.x), ddy(uv.y));

				// from https://github.com/TwoTailsGames/Unity-Built-in-Shaders/blob/master/DefaultResourcesExtra/Internal-DeferredReflections.shader
				float3 color, normal;
				readSurfaceInfo(uv, rayDir, color, normal);
				float3 color0 = color;
				
				// gaussian blur as a first test
				float4 sum = float4(0,0,0,0);
				float numSigmas = 2.5;
				int di = 5;
				float sigma = numSigmas / float(di*di);
				for(int j=-di;j<=di;j++){
					for(int i=-di;i<=di;i++){
						float2 uv2 = uv + float2(i,j) * duv;
						float3 nor = readSurfaceNormal(uv2);
						float4 illumination = tex2D(_Accumulation, uv2);
						// return float4(illumination, 1.0);
						float weight = i == 0 && j == 0 ? 1.0 : exp(-sigma*float(i*i+j*j)) * max(0.0, dot(nor,normal) - 0.8);
						sum += float4(illumination.xyz * (weight / illumination.w), weight);
					}
				}
				color *= sum.xyz * (_Exposure / sum.w);
				// color = HDR_to_LDR(color);
				if(uv.x > _SplitX) return float4(color, 1.0);
				
				return float4(uv.y < _SplitY ? HDR_to_LDR(tex2D(_Accumulation, uv).rgb) : color0, 1.0);
				// return float4(normalize(normal)*.5+.5, 1.0);
				// return float4(frac(log2(depth)), 0.0, 0.0, 1.0);
				// return abs(tex2D(_CameraMotionVectorsTexture, uv)*10.0+0.5);
			}
			ENDCG
		}
	}
}
