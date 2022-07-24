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
        // the id layer is rendering the surfel ID, which must not be mixed
        Blend 3 Max One One
        Cull Front

        Pass {

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
                float4 colorDy: TEXCOORD9;
                int surfelId: TEXCOORD10;
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

            // todo set this to [~1-2]/surfelDensity
            float _IdCutoff;

            // procedural rendering like https://www.ronja-tutorials.com/post/051-draw-procedural/
            v2f vert (uint vertexId: SV_VertexID, uint instanceId: SV_InstanceID) {
                
                v2f o;
                float3 localPos = _Vertices[vertexId];
                UNITY_INITIALIZE_OUTPUT(v2f, o);
                #if defined(SHADER_API_D3D11)
                    int surfelId = instanceId + _InstanceIDOffset;
                    Surfel surfel;
                    if(surfelId < _SurfelCount) {
                        surfel = _Surfels[surfelId];
                        localPos = quatRot(localPos * float3(1.0,1.0,1.0), surfel.rotation) * surfel.position.w + surfel.position.xyz;
                        if(!_VisualizeSurfels && surfel.color.w < 0.0001) localPos = 0; // invalid surfel / surfel without known color
                    } else {
                        localPos = 0; // remove cube visually
                    }
                #endif
                o.vertex = UnityObjectToClipPos(localPos);
                o.screenPos = ComputeScreenPos(o.vertex);
                o.surfelWorldPos = float3(unity_ObjectToWorld[0][3],unity_ObjectToWorld[1][3],unity_ObjectToWorld[2][3]);
                #if defined(SHADER_API_D3D11)
                o.surfelWorldPos += surfel.position.xyz;
                o.color = surfel.color / surfel.color.w;
                o.colorDx = surfel.colorDx / surfel.colorDx.w;
                o.colorDy = surfel.colorDy / surfel.colorDy.w;
                o.invSize = 1.0 / surfel.position.w;
                o.surfelNormal = quatRot(float3(0,1,0), surfel.rotation);
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
                float4 v : SV_TARGET0;
                float4 dx : SV_TARGET1;
                float4 dy : SV_TARGET2;
                int id : SV_TARGET3;
            };

            f2t frag (v2f i) : SV_Target {
                float2 uv = i.screenPos.xy / i.screenPos.w;
                half4 gbuffer0 = tex2D(_CameraGBufferTexture0, uv);
                half4 gbuffer1 = tex2D(_CameraGBufferTexture1, uv);
                half4 gbuffer2 = tex2D(_CameraGBufferTexture2, uv);
                UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
                float specular = SpecularStrength(data.specularColor);
                float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);

                f2t result;

                if(!_AllowSkySurfels && rawDepth == 0.0) {
                    result.v = float4(1,1,1,1);// GI in the sky is 1
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
                // float3 surfaceWorldPosition = WorldPosFromDepth(depth, uv);
                float3 surfaceWorldPosition = _WorldSpaceCameraPos + depth * lookDir;
                float3 surfaceLocalPosition = (surfaceWorldPosition - i.surfelWorldPos) * i.invSize;

                float3 Albedo;
                // Albedo = color;
                // Albedo = normal*.5+.5;
                // Albedo = normalize(surfaceLocalPosition)*.5+.5;
                // Albedo = lookDir;
                // Albedo = frac(log2(depth));
                // return float4(frac(surfaceWorldPosition),1);
                float closeness, geoCloseness;
                float dist = dot(surfaceLocalPosition, surfaceLocalPosition);
                if(rawDepth == 0.0 && dist > 3.0) {

                    // disc like closeness
                    dist = dot(i.localPos.xz,i.localPos.xz);
                    closeness = max(1.0/(1.0+20.0*dist)-0.16667, 0.0);
                    // return float4(closeness,closeness,closeness,1);
                    
                } else {
                    closeness = /*0.001 + 
                        0.999 * */
                        saturate(1.0/(1.0+20.0*dist)-0.1667) *
                        saturate(dot(i.surfelNormal, normal)); // todo does this depend on the roughness maybe? :)
                }

                if(_VisualizeSurfels > 0.0) {
                    result.v = float4(1,1,1,1)*closeness;
                    result.id = closeness < _IdCutoff ? i.surfelId : 0;
                    return result;
                }

                // if(closeness <= 0.0) discard; // without it, we get weird artefacts from too-far-away-surfels
                
                result.v = i.color * closeness;

                 // calculate derivatives

                // use dFdx/y(color) from surfel data
                // for that, transform surfel.colorDx from surfel space into pixel space
                // pixel space -> surfel space; and then inverse that matrix
                float2 dLdx = ddx(surfaceLocalPosition.xz);// can become huge, if dot(viewDir,surfaceNormal) ~ 0
                float2 dLdy = ddy(surfaceLocalPosition.xz);
                float invDet = 1.0 / (dLdx.x*dLdy.y - dLdx.y*dLdy.x);// todo can become NaN

                float2 dxdL = invDet * float2(+dLdy.y, -dLdx.y);
                float2 dydL = invDet * float2(-dLdy.x, +dLdx.x);

                // todo check that this is correct (could be transposed)
                float4 colorDx = dxdL.x * i.colorDx + dxdL.y * i.colorDy;
                float4 colorDy = dydL.x * i.colorDx + dydL.y * i.colorDy;
                result.dx = closeness * colorDx + i.color * ddx(closeness); // ddx_fine is not available
                result.dy = closeness * colorDy + i.color * ddy(closeness);
                result.id = closeness < _IdCutoff ? i.surfelId : 0;
                return result;

                Albedo = float3(closeness,closeness,closeness);
                #ifndef UNITY_INSTANCING_ENABLED
                Albedo.yz = 0;
                #endif
                result.v = float4(Albedo,1.0); return result;
                
            }
            
            ENDCG
        }
    }
}