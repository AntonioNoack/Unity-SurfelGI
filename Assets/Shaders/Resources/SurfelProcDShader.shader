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
            #include "Surfel.cginc"

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

            // set this to [~1-2]/surfelDensity
            float _IdCutoff;

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
                #endif
                o.worldPos = mul(unity_ObjectToWorld, localPos).xyz;
                o.localPos = localPos;
                return o;

            }

			#include "UnityCG.cginc"
            #include "UnityGBuffer.cginc"
			#include "UnityStandardUtils.cginc"

            struct f2t {
                float4 v : SV_TARGET;
                float4 dx : SV_TARGET1;
                float4 dy : SV_TARGET2;
                // int id : SV_TARGET3; // breaks rendering without warnings 😵
            };

            f2t frag (v2f i) {

                float2 uv = i.screenPos.xy / i.screenPos.w;
                half4 gbuffer0 = tex2D(_CameraGBufferTexture0, uv);
                half4 gbuffer1 = tex2D(_CameraGBufferTexture1, uv);
                half4 gbuffer2 = tex2D(_CameraGBufferTexture2, uv);
                UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
                float specular = SpecularStrength(data.specularColor);
                float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);

                f2t result;
                result.v = 1;
                result.dx = 0;
                result.dy = 0;

                if(!_AllowSkySurfels && rawDepth == 0.0) {
                    // GI in the sky is 1
                    return result;
                }

                float depth = LinearEyeDepth(rawDepth);
                
                float3 diff = data.diffuseColor;
                float3 spec = data.specularColor;
                float3 color = diff + spec;
                float3 normal = data.normalWorld;

                // calculate surface world position from depth x direction
                float3 lookDir0 = float3((uv*2.0-1.0)*_FieldOfViewFactor, 1.0);
                float3 lookDir = normalize(i.worldPos - _WorldSpaceCameraPos) * length(lookDir0);
                float3 worldPos = _WorldSpaceCameraPos + depth * lookDir;
                float3 localPos = quatRotInv((worldPos - i.surfelWorldPos) * i.invSize, i.surfelRot);

                float3 Albedo;
                float closeness, geoCloseness;
                float dist = dot(localPos, localPos);
                
                closeness = // 0.001 + 0.999 * 
                    saturate(1.0/(1.0+20.0*dist)-0.1667) *
                    saturate(dot(i.surfelNormal, normal)); // todo does this depend on the roughness maybe? :)
                
                if(!(closeness > 0.0 && closeness <= 1.0 && i.color.w > 0.0)) discard;

                result.v = i.color * closeness;

                float4 estColor = i.color + localPos.x * i.colorDx + localPos.z * i.colorDz;
                float4 colorDx = ddx(estColor);
                float4 colorDy = ddy(estColor);

                result.v = closeness * i.color;//estColor;
                result.dx = closeness * colorDx;
                result.dy = closeness * colorDy;

                // result.dx = float4(localPos.xz*.5+.5,0,1); // surface test
                // result.id = closeness < _IdCutoff ? i.surfelId : 0;
                return result;

                //Albedo = float3(closeness,closeness,closeness);
                //#ifndef UNITY_INSTANCING_ENABLED
                //Albedo.yz = 0;
                //#endif
                //result.v = float4(Albedo,1.0); return result;
                
            }
            
            ENDCG
        }
    }
}