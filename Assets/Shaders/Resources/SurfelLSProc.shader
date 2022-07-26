Shader "Custom/Surfel2ProcShader" {
    Properties {
        _AllowSkySurfels("Allow Sky Surfels", Float) = 0.0
        _VisualizeSurfels("Visualize Surfels", Float) = 0.0
    }
    SubShader {

        Tags { "RenderType" = "Opaque" }
        LOD 100

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
            };
      
            sampler2D _CameraGBufferTexture0;
            sampler2D _CameraGBufferTexture1;
            sampler2D _CameraGBufferTexture2;
            sampler2D _CameraDepthTexture;

            StructuredBuffer<Surfel> _Surfels;
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
                int surfelId = instanceId + _InstanceIDOffset;
                Surfel surfel;
                if(surfelId < _SurfelCount) {
                    surfel = _Surfels[surfelId];
                    // we have a disk/sphere ideally, so localPos doesn't matter anyway
                    // localPos = quatRot(localPos * float3(1.0,1.0,1.0), surfel.rotation) * surfel.position.w + surfel.position.xyz;
                    localPos = localPos * surfel.position.w + surfel.position.xyz;
                    if(!_VisualizeSurfels && surfel.color.w < 0.0001) localPos = 0; // invalid surfel / surfel without known color
                } else {
                    localPos = 0; // remove cube visually
                }
                o.vertex = UnityObjectToClipPos(localPos);
                return o;
            }

			#include "UnityCG.cginc"
            #include "UnityGBuffer.cginc"
			#include "UnityStandardUtils.cginc"

            float4 frag (v2f i) : SV_Target {
                return float4(1,1,1,1);
            }
            
            ENDCG
        }
    }
}