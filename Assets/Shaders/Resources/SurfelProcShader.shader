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
            #include "Surfel.cginc"

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
                o.color   = float4(surfel.color.rgb   / max(surfel.color.w,   1e-10), 1.0);
                o.invSize = 1.0 / surfel.position.w;
                o.surfelNormal = quatRot(float3(0,1,0), surfel.rotation);
                #endif
                o.worldPos = mul(unity_ObjectToWorld, localPos).xyz;
                o.localPos = localPos;
                return o;
            }

			#include "UnityCG.cginc"
            #include "UnityGBuffer.cginc"
			#include "UnityStandardUtils.cginc"

            float4 frag (v2f i) : SV_Target {
                float2 uv = i.screenPos.xy / i.screenPos.w;
                half4 gbuffer0 = tex2D(_CameraGBufferTexture0, uv);
                half4 gbuffer1 = tex2D(_CameraGBufferTexture1, uv);
                half4 gbuffer2 = tex2D(_CameraGBufferTexture2, uv);
                UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
                float specular = SpecularStrength(data.specularColor);
                float rawDepth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);

                if(!_AllowSkySurfels && rawDepth == 0.0) {
                    return float4(1,1,1,1);// GI in the sky is 1
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
                float closeness;
                float dist = dot(surfaceLocalPosition, surfaceLocalPosition);
                if(rawDepth == 0.0 && dist > 3.0) {// sky

                    // disc like closeness
                    dist = length(i.localPos.xz);
                    closeness = max(1.0/(1.0+10.0*dist)-0.16667, 0.0);
                    // return float4(closeness,closeness,closeness,1);
                    
                } else {
                    closeness = /*0.001 + 
                        0.999 * */
                        // todo use linear falloff for linear transitions
                        saturate(1.0/(1.0+20.0*dist)-0.1667) *
                        // saturate(1.0 - 2.0 * sqrt(dist)) *
                        // step(dist, 1.0) *
                        saturate(dot(i.surfelNormal, normal)); // todo does this depend on the roughness maybe? :)
                }

                return i.color * (closeness / i.color.w);

                /*Albedo = float3(closeness,closeness,closeness);
                #ifndef UNITY_INSTANCING_ENABLED
                Albedo.yz = 0;
                #endif
                return float4(Albedo,1.0);*/
                
            }
            
            ENDCG
        }
    }
}