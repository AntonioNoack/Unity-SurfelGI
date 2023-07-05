Shader "RayTracing/Display" {
	Properties {
		_Exposure("Exposure", Range(0.0, 1000.0)) = 1.0
		_SplitX("SplitX", Range(0,1)) = 0.75
		_SplitY("SplitY", Range(0,1)) = 0.50
		_ShowIllumination("Show GI", Float) = 0.0
		_VisualizeSurfels("Visualize Surfels", Float) = 0.0
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

			v2f vert(appdata v) {
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.uv = v.uv;
				return o;
			}

			float _Exposure;
			float _Far;

			float2 _CameraScale;
			float4 _CameraRotation;

			float2 _Duv;

			// Unitys predefined GBuffer data
			sampler2D _CameraGBufferTexture0;
			sampler2D _CameraGBufferTexture1;
			sampler2D _CameraGBufferTexture2;
			sampler2D _CameraDepthTexture;
			samplerCUBE _SkyBox;

			sampler2D _Accumulation;

			float3 quatRot(float3 v, float4 q){
				return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
			}

			float3 getAlbedoColor(float2 uv, float3 dir){
				half4 gbuffer0 = tex2Dlod(_CameraGBufferTexture0, float4(uv,0,0));
				half4 gbuffer1 = tex2Dlod(_CameraGBufferTexture1, float4(uv,0,0));
				half4 gbuffer2 = tex2Dlod(_CameraGBufferTexture2, float4(uv,0,0));
				UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
				float3 color = data.diffuseColor + data.specularColor;
				float depth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
				if(dot(color,color) < 0.01 && depth >= _Far * 0.99){
					color = texCUBE(_SkyBox, dir);
				}
				return color;
			}

			float3 HDR_to_LDR(float3 c){
				return c/(max(max(c.x,c.y),max(c.z,0.0))+1.0);
			}

			float4 frag (v2f i) : SV_Target {

				float2 uv = i.uv;
				float4 ill = tex2Dlod(_Accumulation, float4(uv,0,0));

				float rawDepth = tex2Dlod(_CameraDepthTexture, float4(uv,0,0)).x;
				if(rawDepth > 0.001 && ill.w == 0.0){
					// we miss information: try to get it from neighbors
					[loop]
					for(int r=1;r<=16;r++){
						for(int s=-r;s<r;s++){
							ill += tex2Dlod(_Accumulation, float4(uv + float2(+s,+r) * _Duv, 0, 0));
							ill += tex2Dlod(_Accumulation, float4(uv + float2(+r,-s) * _Duv, 0, 0));
							ill += tex2Dlod(_Accumulation, float4(uv + float2(-r,+s) * _Duv, 0, 0));
							ill += tex2Dlod(_Accumulation, float4(uv + float2(-s,-r) * _Duv, 0, 0));
						}
						if(ill.w > 0.0) break;
					}
					if(!(ill.w > 0.0)) {
						return float4(0.5,0.5,0.5,1.0); // could not be fixed, gray
					}
				}

				if(rawDepth <= 0.001) {
					ill = float4(1,1,1,1);
				}

				float3 rayDir = normalize(quatRot(float3((uv - 0.5) * _CameraScale.xy, 1.0), _CameraRotation));
				float3 color = getAlbedoColor(uv, rayDir);
				float3 hdrColor = color * ill.xyz * (_Exposure / ill.w);
				return float4(HDR_to_LDR(hdrColor), 1.0);

			}
			ENDCG
		}
	}
}
