Shader "Custom/SurfelProcShader" {
    Properties {
        _AllowSkySurfels("Allow Sky Surfels", Float) = 0.0
        _VisualizeSurfels("Visualize Surfels", Float) = 0.0
    }
    SubShader {
        Tags { "RenderType" = "Opaque" }
        LOD 100
        ZTest Always
        ZWrite Off
        Blend One One
        Cull Front

        Pass {

            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma target 3.5

            #include "UnityCG.cginc"

            struct v2f {
                float4 vertex : SV_POSITION;
                float3 worldPos : TEXCOORD1;
                float4 screenPos : TEXCOORD2;
                float3 surfelWorldPos : TEXCOORD3;
                float4 color: TEXCOORD4;
                float invSize: TEXCOORD5;
                float3 surfelNormal: TEXCOORD6; // in world space
                float3 localPos : TEXCOORD7;
            };
      
            sampler2D _CameraGBufferTexture0;
            sampler2D _CameraGBufferTexture1;
            sampler2D _CameraGBufferTexture2;
            sampler2D _CameraDepthTexture;

            struct Surfel {
                float4 position;
                float4 rotation;
                float4 color;
            };

        #ifdef SHADER_API_D3D11
            StructuredBuffer<Surfel> _Surfels : register(t1);
        #endif

            StructuredBuffer<float3> _Vertices;

            // global property
            int _InstanceIDOffset;
            int _SurfelCount;

            float2 _FieldOfViewFactor;

            float _AllowSkySurfels;
            float _VisualizeSurfels;

            float3 quatRot(float3 v, float4 q) {
				return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
			}

            float3 _CameraPos;

            float4x4 _CustomMVP;
            float4 UnityObjectToClipPos2(float3 pos) {
                return mul(_CustomMVP, float4(pos, 1.0));
            }

            // procedural rendering like https://www.ronja-tutorials.com/post/051-draw-procedural/
            v2f vert (uint vertexId: SV_VertexID, uint instanceId: SV_InstanceID) {
                
                v2f o;
                float3 localPos = _Vertices[vertexId];
                float3 localPos0 = localPos;
                #if defined(SHADER_API_D3D11)
                    int surfelId = instanceId + _InstanceIDOffset;
                    Surfel surfel;
                    if(surfelId < _SurfelCount) {
                        surfel = _Surfels[surfelId];
                        float surfelSize = surfel.position.w;
                        localPos = quatRot(localPos * float3(1.0,0.2,1.0), surfel.rotation) * surfelSize + surfel.position.xyz;
                        if(!_VisualizeSurfels && surfel.color.w < 0.0001) localPos = 0; // invalid surfel / surfel without known color
                    } else {
                        localPos = 0; // remove cube visually
                    }
                    o.vertex = UnityObjectToClipPos(localPos);
                    o.screenPos = ComputeScreenPos(o.vertex);
                    o.surfelWorldPos = surfel.position.xyz;
                    o.color = surfel.color;
                    o.invSize = 1.0 / surfel.position.w;
                    o.surfelNormal = quatRot(float3(0,1,0), surfel.rotation);
                    o.worldPos = surfel.position.xyz + localPos;
                    o.localPos = localPos0;
                #else
                    o.vertex = 0;
                    o.worldPos = 0;
                    o.localPos = 0;
                    o.screenPos = 0;
                    o.surfelWorldPos = 0;
                #endif
                return o;
            }

			#include "UnityCG.cginc"
            #include "UnityGBuffer.cginc"
			#include "UnityStandardUtils.cginc"

            float4 frag (v2f i) : SV_Target {

                // return i.color;

                float2 uv = i.screenPos.xy / i.screenPos.w;
                // return float4(uv,0,1);

                half4 gbuffer0 = tex2D(_CameraGBufferTexture0, uv);
                half4 gbuffer1 = tex2D(_CameraGBufferTexture1, uv);
                half4 gbuffer2 = tex2D(_CameraGBufferTexture2, uv);
                UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
                float specular = SpecularStrength(data.specularColor);
                float rawDepth = tex2D(_CameraDepthTexture, uv).r;

                if(!_AllowSkySurfels && rawDepth == 0.0) {
                    return float4(1,1,1,1);// GI in the sky is 1
                }

                float depth = LinearEyeDepth(rawDepth);
                // float depth = 0.1/rawDepth;
                // float depth = 100.0 * rawDepth;
                
                float3 diff = data.diffuseColor;
                float3 spec = data.specularColor;
                float3 color = diff + spec;
                float3 normal = data.normalWorld;

                // calculate surface world position from depth x direction
                float3 lookDir0 = float3((uv*2.0-1.0) * _FieldOfViewFactor, 1.0);
                float3 lookDir = normalize(i.worldPos - _CameraPos) * length(lookDir0);
                // float3 surfaceWorldPosition = WorldPosFromDepth(depth, uv);
                float3 surfaceWorldPosition = _CameraPos + depth * lookDir;
                // return float4(frac(log2(depth)),frac(log2(depth)),frac(log2(depth)),1);
                float3 surfaceLocalPosition = (surfaceWorldPosition - i.surfelWorldPos) * i.invSize;

                float3 Albedo;
                // Albedo = color;
                // Albedo = normal*.5+.5;
                // Albedo = normalize(surfaceLocalPosition)*.5+.5;
                // Albedo = lookDir;
                Albedo = frac(log2(depth));
                // return float4(Albedo,1);
                // return float4(frac(i.surfelWorldPos),1);
                return float4(frac(surfaceWorldPosition),1);
                float closeness;
                float dist = dot(surfaceLocalPosition, surfaceLocalPosition);
                return float4(frac(dist),frac(dist),frac(dist),1);
                if(rawDepth == 0.0 && dist > 3.0) {

                    // disc like closeness
                    dist = length(i.localPos.xz);
                    closeness = max(1.0/(1.0+10.0*dist)-0.16667, 0.0);
                    // return float4(closeness,closeness,closeness,1);
                    
                } else {
                    closeness = /*0.001 + 
                        0.999 * */
                        saturate(1.0/(1.0+20.0*dist)-0.1667) *
                        saturate(dot(i.surfelNormal, normal)*25.0-24.0);
                }

                if(_VisualizeSurfels > 0.0) return float4(1,1,1,1)*closeness;
                // if(closeness <= 0.0) discard; // without it, we get weird artefacts from too-far-away-surfels
                return i.color * (closeness / i.color.w);
                Albedo = float3(closeness,closeness,closeness);
                #ifndef UNITY_INSTANCING_ENABLED
                Albedo.yz = 0;
                #endif
                return float4(Albedo,1.0);
                
            }
            
            ENDCG
        }
    }
}
