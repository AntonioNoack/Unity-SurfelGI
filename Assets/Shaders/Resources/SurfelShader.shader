Shader "Custom/SurfelShader" {
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
            #include "UnityGBuffer.cginc"
			#include "UnityStandardUtils.cginc"

            #include "Common.cginc"
            #include "Surfel.cginc"

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
                float2 surfelData: TEXCOORD8;
                int surfelId: TEXCOORD9;
                // UNITY_VERTEX_OUTPUT_STEREO
            };
            
            sampler2D _CameraGBufferTexture0;
            sampler2D _CameraGBufferTexture1;
            sampler2D _CameraGBufferTexture2;
            sampler2D _CameraDepthTexture;

        #ifdef SHADER_API_D3D11
            uniform StructuredBuffer<Surfel> _Surfels : register(t1);
        #endif

            // global property
            int _InstanceIDOffset;
            int _SurfelCount;

            float2 _FieldOfViewFactor;

            float _AllowSkySurfels;
            float _VisualizeSurfels;
            float _VisualizeSurfelIds;

            v2f vert (appdata v) {
                v2f o;
                float3 localPos = v.vertex;
                #ifdef UNITY_INSTANCING_ENABLED
                UNITY_SETUP_INSTANCE_ID(v);
                #endif
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                #if defined(UNITY_INSTANCING_ENABLED) && defined(SHADER_API_D3D11)
                    int surfelId = unity_InstanceID + _InstanceIDOffset;
                    o.surfelId = surfelId;
                    Surfel surfel = (Surfel) 0;
                    if(surfelId < _SurfelCount) {
                        surfel = _Surfels[surfelId]; // does work, but only for DrawMeshInstanced
                        v.vertex.xyz = quatRot(v.vertex.xyz * float3(1.0,0.2,1.0), surfel.rotation) * surfel.position.w + surfel.position.xyz;
                        if(!_VisualizeSurfels && surfel.color.w < 0.0001) v.vertex = 0; // invalid surfel / surfel without known color
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
                o.surfelData = surfel.data.yz;
                #endif
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.localPos = localPos;
                return o;
            }

            float4 frag (v2f i) : SV_Target {

                float2 uv = i.screenPos.xy / i.screenPos.w;
                
                float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
                if(rawDepth == 0.0) discard; // sky surfels are ignored

                half4 gbuffer0 = tex2D(_CameraGBufferTexture0, uv);
                half4 gbuffer1 = tex2D(_CameraGBufferTexture1, uv);
                half4 gbuffer2 = tex2D(_CameraGBufferTexture2, uv);
                UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
                float specular = SpecularStrength(data.specularColor);
                float smoothness = data.smoothness;

                float depth = LinearEyeDepth(rawDepth);
                
                float3 diff = data.diffuseColor;
                float3 spec = data.specularColor;
                float3 color = diff + spec;
                float3 normal = data.normalWorld;

                // calculate surface world position from depth x direction
                float3 lookDir0 = mul((float3x3) UNITY_MATRIX_V, float3((uv*2.0-1.0)*_FieldOfViewFactor, 1.0));
                float3 lookDir = normalize(i.worldPos - _WorldSpaceCameraPos) * length(lookDir0);
                
                float3 surfaceWorldPosition = _WorldSpaceCameraPos + depth * lookDir;
                float3 localPosition = (surfaceWorldPosition - i.surfelWorldPos) * i.invSize;

                #include "SurfelWeight.cginc"
                
                if(weight <= 0.0) discard;

                if(_VisualizeSurfels > 0.0) return float4(1,1,1,1)*weight;
                return i.color * (weight / i.color.w);
                
            }
            
            ENDCG
        }
    }
}
