Shader "RayTracing/LightSampleAABBs" {
    Properties {}

    SubShader {
        Tags { "RenderType" = "Opaque" "DisableBatching" = "True"}
        LOD 100

        Pass {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            struct appdata {
                float4 vertex : POSITION;
            };

            struct v2f {
                float4 vertex : SV_POSITION;
            };

            v2f vert (appdata v) {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target {
                return fixed4(1, 1, 1, 1);
            }
            ENDCG
        }
    }

    SubShader {
        Pass {
            Name "Test"
            Tags { "LightMode" = "RayTracing" }

            HLSLPROGRAM

            #include "RTLib.cginc"
            #include "Surfel.cginc"

            #pragma raytracing test

            #pragma multi_compile_local __ RAY_TRACING_PROCEDURAL_GEOMETRY

            StructuredBuffer<Surfel> g_Surfels;

            [shader("intersection")]
            void BoxIntersectionMain() {
                Surfel surfel = g_Surfels[PrimitiveIndex()];

                float3 pos = surfel.position.xyz;
                float size = surfel.position.w;
                float3 dir = quatRot(float3(0,1,0), surfel.rotation);
                float t = dot(WorldRayDirection(), (pos - WorldRayOrigin()));

                // only hit, if surfel is close enough
                float3 hitPosition = WorldRayOrigin() + t * WorldRayDirection();
                float3 delta = hitPosition - pos;
                float distSq = dot(delta,delta);
                if (t > 0.0 && distSq < size * size && dot(dir, WorldRayDirection()) < 0.0) {
                    AttributeData attr = (AttributeData) 0;
                    ReportHit(t, 0, attr);
                }
            }

            [shader("closesthit")]
            void ClosestHitMain(inout RayPayload payload : SV_RayPayload, in AttributeData attribs : SV_IntersectionAttributes) {
                // todo modulate weight by direction-alignment (?)
                Surfel surfel = g_Surfels[PrimitiveIndex()];
                payload.surfelId = PrimitiveIndex();
                float radius = surfel.position.w;
                float area = PI * radius * radius;
                // todo reenable?
                // payload.weight /= area;// large surfels are impacted less by photons
            }

            ENDHLSL
        }
    }
}
