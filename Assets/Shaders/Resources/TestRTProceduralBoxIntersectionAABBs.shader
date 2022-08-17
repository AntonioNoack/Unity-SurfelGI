Shader "RayTracing/ProceduralBoxIntersectionAABBs" {
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

            #include "Common.cginc"
            #include "Surfel.cginc"

            #pragma raytracing test

            #pragma multi_compile_local __ RAY_TRACING_PROCEDURAL_GEOMETRY

            StructuredBuffer<AABB> g_AABBs;
            StructuredBuffer<Surfel> g_Surfels;

#if RAY_TRACING_PROCEDURAL_GEOMETRY

            bool RayBoxIntersectionTest(in float3 rayWorldOrigin, in float3 rayWorldDirection, in float3 boxPosWorld, in float3 boxHalfSize,
                out float outHitT, out float3 outNormal, out float2 outUVs, out int outFaceIndex) {
                // convert from world to box space
                float3 rd = rayWorldDirection;
                float3 ro = rayWorldOrigin - boxPosWorld;

                // ray-box intersection in box space
                float3 m = 1.0 / rd;
                float3 s = float3(
                    (rd.x < 0.0) ? 1.0 : -1.0,
                    (rd.y < 0.0) ? 1.0 : -1.0,
                    (rd.z < 0.0) ? 1.0 : -1.0);

                float3 t1 = m * (-ro + s * boxHalfSize);
                float3 t2 = m * (-ro - s * boxHalfSize);

                float tN = max(max(t1.x, t1.y), t1.z);
                float tF = min(min(t2.x, t2.y), t2.z);
                outHitT = tN;

                return tN <= tF && tF >= 0.0;

            }

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

#endif

            [shader("closesthit")]
            void ClosestHitMain(inout RayPayload payload : SV_RayPayload, in AttributeData attribs : SV_IntersectionAttributes) {
                // todo modulate weight by direction-alignment (?)
                Surfel surfel = g_Surfels[PrimitiveIndex()];
                payload.surfelId = PrimitiveIndex();
                float radius = surfel.position.w;
                float area = PI * radius * radius;
                payload.weight /= area;// large surfels are impacted less by photons
            }

            ENDHLSL
        }
    }
}
