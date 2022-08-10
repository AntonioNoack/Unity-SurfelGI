Shader "RayTracing/883/ProceduralBoxIntersection"
{
    Properties
    {
        _Color("Main Color", Color) = (1, 1, 1, 1)
    }

    SubShader
    {
        Tags { "RenderType" = "Opaque" "DisableBatching" = "True"}
        LOD 100

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"

            float4 _Color;

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
                return _Color;
            }
            ENDCG
        }
    }

    SubShader {
        Pass {
            Name "Test"

            Tags{ "LightMode" = "RayTracing" }

            HLSLPROGRAM

            #include "../Shader/Resources/Common.cginc"

            #pragma raytracing test

            #pragma multi_compile_local __ RAY_TRACING_PROCEDURAL_GEOMETRY

            float4 _Color;

#if RAY_TRACING_PROCEDURAL_GEOMETRY

            float RayBoxIntersect(float3 orig, float3 dir, float3 aabbmin, float3 aabbmax) {
                float3 invDir = 1.0f / dir;

                float t1 = (aabbmin.x - orig.x) * invDir.x;
                float t2 = (aabbmax.x - orig.x) * invDir.x;
                float t3 = (aabbmin.y - orig.y) * invDir.y;
                float t4 = (aabbmax.y - orig.y) * invDir.y;
                float t5 = (aabbmin.z - orig.z) * invDir.z;
                float t6 = (aabbmax.z - orig.z) * invDir.z;

                float tmin = max(max(min(t1, t2), min(t3, t4)), min(t5, t6));
                float tmax = min(min(max(t1, t2), max(t3, t4)), max(t5, t6));

                if (tmin < 0 || tmax < tmin)
                    return -1;
                else
                    return tmin;
            }

            [shader("intersection")]
            void BoxIntersectionMain() {
                float t = RayBoxIntersect(ObjectRayOrigin(), ObjectRayDirection(), float3(-0.5, -0.5, -0.5), float3(0.5, 0.5, 0.5));
                if (t > 0) {
                    AttributeData attr;
                    attr.barycentrics = float2(0, 0);
                    ReportHit(t, 0, attr);
                }
            }

#endif

            [shader("closesthit")]
            void ClosestHitMain(inout RayPayload payload : SV_RayPayload, in AttributeData attribs : SV_IntersectionAttributes) {
                payload.color = _Color;
            }

            ENDHLSL
        }
    }
}
