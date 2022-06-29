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

        CGPROGRAM
        // Physically based Standard lighting model, and enable shadows on all light types
        #pragma surface surf Standard fullforwardshadows vertex:vert

        // Use shader model 3.0 target, to get nicer looking lighting
        #pragma target 3.5

        struct Input {
            float2 uv_MainTex;
            float3 worldPos;
            float4 screenPos; // defined by Unity
            float3 surfelWorldPos;
        };
        
		// GBuffer for metallic & roughness
		sampler2D _CameraGBufferTexture0;
		sampler2D _CameraGBufferTexture1;
		sampler2D _CameraGBufferTexture2;
		sampler2D _CameraDepthTexture;

        // Add instancing support for this shader. You need to check 'Enable Instancing' on materials that use the shader.
        // See https://docs.unity3d.com/Manual/GPUInstancing.html for more information about instancing.
        // #pragma instancing_options assumeuniformscaling
        UNITY_INSTANCING_BUFFER_START(Props)
            // put more per-instance properties here
        UNITY_INSTANCING_BUFFER_END(Props)

        void vert(inout appdata_full v, out Input o) {
            UNITY_INITIALIZE_OUTPUT(Input, o);
            o.surfelWorldPos = float3(unity_ObjectToWorld[0][3],unity_ObjectToWorld[1][3],unity_ObjectToWorld[2][3]);
            o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
        }

        float2 _FieldOfViewFactor;

        // possible optimizations:
        // copying depth, and then using depth-test: https://forum.unity.com/threads/how-do-i-copy-depth-to-the-camera-target-in-unitys-srp.713024/

        void surf(Input i, inout SurfaceOutputStandard o) {

            float2 uv = i.screenPos.xy / i.screenPos.w;
            half4 gbuffer0 = tex2D(_CameraGBufferTexture0, uv);
			half4 gbuffer1 = tex2D(_CameraGBufferTexture1, uv);
			half4 gbuffer2 = tex2D(_CameraGBufferTexture2, uv);
			UnityStandardData data = UnityStandardDataFromGbuffer(gbuffer0, gbuffer1, gbuffer2);
			float specular = SpecularStrength(data.specularColor);
			float depth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
			// float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv);
			// float depth = DECODE_EYEDEPTH(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
            
			float3 diff = data.diffuseColor;
			float3 spec = data.specularColor;
            float3 color = diff + spec;
            float3 normal = data.normalWorld;

            // calculate surface world position from depth x direction
            float3 lookDir0 = mul((float3x3) UNITY_MATRIX_V, float3((uv*2.0-1.0)*_FieldOfViewFactor, 1.0));
            float3 lookDir = normalize(i.worldPos - _WorldSpaceCameraPos) * length(lookDir0);
            // float3 surfaceWorldPosition = WorldPosFromDepth(depth, uv);
            float3 surfaceWorldPosition = _WorldSpaceCameraPos + depth * lookDir;
            float3 surfaceLocalPosition = surfaceWorldPosition - i.surfelWorldPos;

            // todo use better falloff function
            // todo encode direction in surfel, and use normal-alignment for weight

            // todo position surfels by compute shader & ray tracing
            // todo write light data into surfels

            // o.Albedo = normalize(i.surfelWorldPos)*.5+.5;
            o.Albedo = color;
            // o.Albedo = normal*.5+.5;
            // o.Albedo = normalize(surfaceLocalPosition)*.5+.5;
            float closeness = saturate(1.0 - 2.0 * length(surfaceLocalPosition));
            if(closeness <= 0.0) discard; // without it, we get weird artefacts from too-far-away-surfels
            // float closeness = frac(length(surfaceLocalPosition)); // much too uniform, why???
            // float closeness = frac(depth);
            o.Albedo = float3(closeness,closeness,closeness);
            // o.Albedo = frac(length(lookDir));
            // o.Albedo = frac(depth);
            // o.Albedo = frac(surfaceWorldPosition);

            // Metallic and smoothness come from slider variables
            o.Metallic = 0.0;
            o.Smoothness = 0.0;
            o.Alpha = 1.0;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
