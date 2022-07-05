Shader "Custom/SurfelShader" {
    Properties {
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

            struct appdata {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                uint instanceID : SV_InstanceID;
            };

            struct v2f {
                float4 vertex : SV_POSITION;
                float3 worldPos : TEXCOORD1;
                float4 screenPos : TEXCOORD2; // defined by Unity
                float3 surfelWorldPos : TEXCOORD3;
                float4 color: TEXCOORD4;
                float invSize: TEXCOORD5;
                float3 surfelNormal: TEXCOORD6; // in world space
                float3 localPos : TEXCOORD7;
                // UNITY_VERTEX_OUTPUT_STEREO
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
            uniform StructuredBuffer<Surfel> _Surfels : register(t1);
        #endif

            // global property
            int _InstanceIDOffset;
            int _SurfelCount;

            float3 quatRot(float3 v, float4 q){
				return v + 2.0 * cross(q.xyz, cross(q.xyz, v) + q.w * v);
			}

            v2f vert (appdata v) {
                v2f o;
                float3 localPos = v.vertex;
                #ifdef UNITY_INSTANCING_ENABLED
                UNITY_SETUP_INSTANCE_ID(v);
                #endif
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                #if defined(UNITY_INSTANCING_ENABLED) && defined(SHADER_API_D3D11)
                    int surfelId = unity_InstanceID + _InstanceIDOffset;
                    Surfel surfel;
                    if(surfelId < _SurfelCount) {
                        // Surfel surfel = _Surfels[min(unity_InstanceID, _Surfels.Length)]; // doesn't work
                        surfel = _Surfels[surfelId]; // does work, but only for DrawMeshInstanced
                        // InitIndirectDrawArgs(0); "unexpected identifier 'ByteAddressBuffer'"
                        // uint cmdID = GetCommandID(0);
                        // uint instanceID = GetIndirectInstanceID(svInstanceID);
                        // Surfel surfel = _Surfels[min(instanceID, 255)]; 
                        v.vertex.xyz = quatRot(v.vertex.xyz * float3(1.0,0.2,1.0), surfel.rotation) * surfel.position.w + surfel.position.xyz;
                        if(surfel.color.w < 0.0001) v.vertex = 0; // invalid surfel / surfel without known color
                    } else {
                        v.vertex = 0; // remove cube visually
                    }
                #endif
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.screenPos = ComputeScreenPos(o.vertex);
                o.surfelWorldPos = float3(unity_ObjectToWorld[0][3],unity_ObjectToWorld[1][3],unity_ObjectToWorld[2][3]);
                #if defined(UNITY_INSTANCING_ENABLED) && defined(SHADER_API_D3D11)
                o.surfelWorldPos += surfel.position.xyz;
                o.color = surfel.color;
                o.invSize = 1.0 / surfel.position.w;
                o.surfelNormal = quatRot(float3(0,1,0), surfel.rotation);
                #endif
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.localPos = localPos;
                return o;
            }

			#include "UnityCG.cginc"
            #include "UnityGBuffer.cginc"
			#include "UnityStandardUtils.cginc"

            float2 _FieldOfViewFactor;

            float4 frag (v2f i) : SV_Target {
                float2 uv = i.screenPos.xy / i.screenPos.w;
                half4 gbuffer0 = tex2D(_CameraGBufferTexture0, uv);
                half4 gbuffer1 = tex2D(_CameraGBufferTexture1, uv);
                half4 gbuffer2 = tex2D(_CameraGBufferTexture2, uv);
                UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
                float specular = SpecularStrength(data.specularColor);
                float depth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
                
                float3 diff = data.diffuseColor;
                float3 spec = data.specularColor;
                float3 color = diff + spec;
                float3 normal = data.normalWorld;

                // calculate surface world position from depth x direction
                float3 lookDir0 = mul((float3x3) UNITY_MATRIX_V, float3((uv*2.0-1.0)*_FieldOfViewFactor, 1.0));
                float3 lookDir = normalize(i.worldPos - _WorldSpaceCameraPos) * length(lookDir0);
                // float3 surfaceWorldPosition = WorldPosFromDepth(depth, uv);
                float3 surfaceWorldPosition = _WorldSpaceCameraPos + depth * lookDir;
                float3 surfaceLocalPosition = (surfaceWorldPosition - i.surfelWorldPos) * i.invSize;

                // todo update surfel transform properly
                // todo update light data in surfels via raytracing
                
                float3 Albedo;
                // Albedo = color;
                // Albedo = normal*.5+.5;
                // Albedo = normalize(surfaceLocalPosition)*.5+.5;
                // Albedo = lookDir;
                // Albedo = frac(log2(depth));
                // Albedo = frac(surfaceWorldPosition);
                float closeness;
                float dist = dot(surfaceLocalPosition, surfaceLocalPosition);
                if(depth > 500.0 && dist > 3.0) {

                    // disc like closeness
                    dist = length(i.localPos.xz);
                    closeness = max(1.0/(1.0+10.0*dist)-0.16667, 0.0);
                    // return float4(closeness,closeness,closeness,1);
                    
                } else {
                    closeness = /*0.001 + 
                        0.999 * */
                        max(1.0/(1.0+10.0*dist)-0.1667, 0.0) *
                        max(dot(i.surfelNormal, normal), 0.0);
                }

                // return float4(closeness,closeness,closeness,1);
                if(closeness <= 0.0) discard; // without it, we get weird artefacts from too-far-away-surfels
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
