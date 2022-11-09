Shader "Custom/Surfel2ProcShader" {
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
        // BlendOp Max
        Cull Front

        Pass {
			Name "EmissivePass"

            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma target 3.5

            #include "UnityCG.cginc"
            #include "UnityGBuffer.cginc"
			#include "UnityStandardUtils.cginc"
            
            #include "Surfel.cginc"
            #include "Common.cginc"

            struct v2f {
                float4 vertex : SV_POSITION;
                float3 worldPos : TEXCOORD1;
                float4 screenPos : TEXCOORD2;
                float3 surfelWorldPos : TEXCOORD3;
                float invSize: TEXCOORD4;
                float3 surfelNormal: TEXCOORD5; // in world space
                float3 localPos : TEXCOORD6;
                float4 color: TEXCOORD7;
                float4 colorDx: TEXCOORD8;
                float4 colorDz: TEXCOORD9;
                int surfelId: TEXCOORD10;
                float4 surfelRot: TEXCOORD11;
                float2 surfelData: TEXCOORD12;
            };
      
            sampler2D _CameraGBufferTexture0;
            sampler2D _CameraGBufferTexture1;
            sampler2D _CameraGBufferTexture2;
            sampler2D _CameraDepthTexture;

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
            float _VisualizeSurfelIds;

            // set this to [~1-2]/surfelDensity
            float _IdCutoff;
            float2 _Duv;

            // procedural rendering like https://www.ronja-tutorials.com/post/051-draw-procedural/
            v2f vert (uint vertexId: SV_VertexID, uint instanceId: SV_InstanceID) {
                
                v2f o;
                float3 localPos = _Vertices[vertexId];
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                #if defined(SHADER_API_D3D11)
                    int surfelId = instanceId + _InstanceIDOffset;
                    Surfel surfel = (Surfel) 0;
                    if(surfelId < _SurfelCount) {
                        surfel = _Surfels[surfelId];
                    }
                    localPos = quatRot(localPos, surfel.rotation) * surfel.position.w + surfel.position.xyz;
                    if(!_VisualizeSurfels && surfel.color.w < 0.0001) localPos = 0; // invalid surfel / surfel without known color
                #endif
                o.vertex = UnityObjectToClipPos(localPos);
                o.screenPos = ComputeScreenPos(o.vertex);
                o.surfelWorldPos = float3(unity_ObjectToWorld[0][3],unity_ObjectToWorld[1][3],unity_ObjectToWorld[2][3]);
                #if defined(SHADER_API_D3D11)
                o.surfelWorldPos += surfel.position.xyz;
                o.color   = float4(surfel.color.rgb   / max(surfel.color.w,   1e-10), 1.0);
                o.colorDx = float4(surfel.colorDx.rgb / max(surfel.colorDx.w, 1e-10), 1.0);
                o.colorDz = float4(surfel.colorDz.rgb / max(surfel.colorDz.w, 1e-10), 1.0);
                o.invSize = 1.0 / max(surfel.position.w, 1e-15);
                o.surfelNormal = quatRot(float3(0,1,0), surfel.rotation);
                o.surfelRot = surfel.rotation;
                o.surfelId = surfelId;
                o.surfelData = surfel.data.yz; // specular, smoothness
                #endif
                o.worldPos = mul(unity_ObjectToWorld, localPos).xyz;
                o.localPos = localPos;
                return o;

            }

            struct f2t {
                float4 v : SV_TARGET;
                float4 dx : SV_TARGET1;
                float4 dy : SV_TARGET2;
                // int id : SV_TARGET3; // breaks rendering without warnings 😵
            };

            float4 sample(v2f i, float2 uv, float2 duv) {

                float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
                if(rawDepth == 0.0) return float4(1,1,1,1);// sky surfels are ignored and have GI = 1.0

                half4 gbuffer0 = tex2D(_CameraGBufferTexture0, uv);
                half4 gbuffer1 = tex2D(_CameraGBufferTexture1, uv);
                half4 gbuffer2 = tex2D(_CameraGBufferTexture2, uv);
                UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
                float specular = SpecularStrength(data.specularColor);
                float smoothness = data.smoothness;

                f2t result;
                result.v = 1;
                result.dx = 0;
                result.dy = 0;

                float depth = LinearEyeDepth(rawDepth);
                
                float3 diff = data.diffuseColor;
                float3 spec = data.specularColor;
                float3 color = diff + spec;
                float3 normal = data.normalWorld;

                // calculate surface world position from depth x direction
                float3 lookDir0 = float3((uv*2.0-1.0)*_FieldOfViewFactor, 1.0);
                float3 worldPos0 = i.worldPos + ddx(i.worldPos) * duv.x + ddy(i.worldPos) * duv.y;
                float3 lookDir = normalize(worldPos0 - _WorldSpaceCameraPos) * length(lookDir0);
                float3 worldPos = _WorldSpaceCameraPos + depth * lookDir;
                float3 localPosition = quatRotInv((worldPos - i.surfelWorldPos) * i.invSize, i.surfelRot);

                #include "SurfelWeight.cginc"
                
                // estimated color for easy gradient calculation
                float3 estColor = i.color.xyz + (localPosition.x * i.colorDx.xyz + localPosition.z * i.colorDz.xyz);
                return float4(estColor, weight);
            }

            f2t frag (v2f i) {

                // ddx, ddy are not good enough; we need to have exactly our definition of a (-1,0,+1) kernel for gradient calculation
                float2 uv = i.screenPos.xy / i.screenPos.w;

                float4 c0 = sample(i,uv,float2(0,0));
                float4 px = sample(i,uv+float2(+_Duv.x,0),float2(+1,0));
                float4 mx = sample(i,uv+float2(-_Duv.x,0),float2(-1,0));
                float4 py = sample(i,uv+float2(0,+_Duv.y),float2(0,+1));
                float4 my = sample(i,uv+float2(0,-_Duv.y),float2(0,-1));

                f2t result;
                result.v = float4(c0.xyz * c0.w, c0.w);
                result.dx = float4((px-mx).rgb * c0.w * 0.5, c0.w);// * 0.5, because we have finite differences over 2 pixels
                result.dy = float4((py-my).rgb * c0.w * 0.5, c0.w);

                return result;

            }
            
            ENDCG
        }
    }
}