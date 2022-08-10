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

            #pragma raytracing test

            #pragma multi_compile_local __ RAY_TRACING_PROCEDURAL_GEOMETRY

            StructuredBuffer<AABB> g_AABBs;
            StructuredBuffer<float4> g_Colors;

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
                AABB aabb = g_AABBs[PrimitiveIndex()];

                float3 aabbPos = (aabb.min + aabb.max) * 0.5f;
                float3 aabbSize = aabb.max - aabb.min;

                float outHitT = 0;
                float3 outNormal = float3(1, 0, 0);
                float2 outUVs = float2(0, 0);
                int outFaceIndex = 0;

                bool isHit = RayBoxIntersectionTest(WorldRayOrigin(), WorldRayDirection(), aabbPos, aabbSize * 0.5, outHitT, outNormal, outUVs, outFaceIndex);

                if (isHit) {
                    AttributeData attr;
                    attr.normal = outNormal;
                    ReportHit(outHitT, 0, attr);
                }
            }

#endif

            [shader("closesthit")]
            void ClosestHitMain(inout RayPayload payload : SV_RayPayload, in AttributeData attribs : SV_IntersectionAttributes) {
                float c = frac(log2(RayTCurrent()));
                payload.color.xyz = float3(c,c,c);// g_Colors[PrimitiveIndex()].xyz;
                payload.surfelIndex = PrimitiveIndex();
            }

            ENDHLSL
        }
    }
}
