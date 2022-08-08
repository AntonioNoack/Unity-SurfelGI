Shader "RayTracing/883/ProceduralSphereIntersection"
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

            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
            };

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                fixed4 col = _Color;

                return col;
            }
            ENDCG
        }
    }

    SubShader
    {
        Pass
        {
            Name "Test"

            Tags{ "LightMode" = "RayTracing" }

            HLSLPROGRAM

            #include "RayPayload.hlsl"

            #pragma raytracing test

            #pragma multi_compile_local __ RAY_TRACING_PROCEDURAL_GEOMETRY

            float4 _Color;

            struct AttributeData
            {
                float2 barycentrics;
            };

#if RAY_TRACING_PROCEDURAL_GEOMETRY

            float RaySphereIntersect(float3 orig, float3 dir, float radius)
            {
                float a = dot(dir, dir);
                float b = 2 * dot(orig, dir);
                float c = dot(orig, orig) - radius * radius;
                float delta2 = b * b - 4 * a * c;
                float t = -1.0f;

                if (delta2 >= 0)
                {
                    float t0 = (-b + sqrt(delta2)) / (2 * a);
                    float t1 = (-b - sqrt(delta2)) / (2 * a);

                    // Get the smallest root larger than 0 (t is in object space);
                    t = max(t0, t1);

                    if (t0 >= 0)
                        t = min(t, t0);

                    if (t1 >= 0)
                        t = min(t, t1);

                    float3 localPos = orig + t * dir;

                    float3 worldPos = mul(ObjectToWorld(), float4(localPos, 1));

                    t = length(worldPos - WorldRayOrigin());
                }

                return t;
            }

            [shader("intersection")]
            void ProceduralSphereIntersectionMain()
            {
                const float radius = 0.495;

                float t = RaySphereIntersect(ObjectRayOrigin(), ObjectRayDirection(), radius);

                if (t > 0)
                {
                    AttributeData attr;
                    attr.barycentrics = float2(0, 0);

                    ReportHit(t, 0, attr);
                }
            }

#endif

            [shader("closesthit")]
            void ClosestHitMain(inout RayPayload payload : SV_RayPayload, in AttributeData attribs : SV_IntersectionAttributes)
            {
                payload.color = _Color;
            }

            ENDHLSL
        }
    }
}
