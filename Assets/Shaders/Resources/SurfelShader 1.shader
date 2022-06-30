Shader "Custom/SurfelShader" {
    Properties {
    }
    SubShader {
        Tags { "RenderType" = "Opaque" }
        LOD 200
        Blend One One // additive blending
        ZWrite Off
        ZTest Always // can be changed to farther in the future
        Cull Front

        Pass {

            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "UnityCG.cginc"

            struct appdata {
                float4 vertex : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f {
                float4 vertex : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            UNITY_INSTANCING_BUFFER_START(Props)
                // UNITY_DEFINE_INSTANCED_PROP(float4, _Color)
            UNITY_INSTANCING_BUFFER_END(Props)

            v2f vert(appdata v) {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                o.vertex = UnityObjectToClipPos(v.vertex);
                return o;
            }

            fixed4 frag(v2f i) : SV_Target {
                UNITY_SETUP_INSTANCE_ID(i);
                // UNITY_ACCESS_INSTANCED_PROP(Props, _Color);
                return float4(1,0,0,1);
            }

            ENDCG
        }

    }
    // FallBack "Diffuse"
}
