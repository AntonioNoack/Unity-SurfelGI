Shader "RayTracing/DxrDiffuseTr" {
	Properties {
		_Color ("Color", Color) = (1, 1, 1, 1)
		_MainTex ("Albedo", 2D) = "white" { }
		_Metallic ("Metallic", Range(0, 1)) = 0.0
		_Glossiness ("Smoothness", Range(0, 1)) = 0.5
	}
	SubShader {
		// if the material is fully opaque, you can set it to Opaque, otherwise use Transparent.
		// using opaque will ignore the anyhit shader
		Tags { "RenderType" = "Transparent" }
		// Tags { "RenderType" = "Opaque" }
		LOD 100

		// basic pass for GBuffer
		CGPROGRAM
		#pragma surface surf Standard fullforwardshadows

		UNITY_INSTANCING_BUFFER_START(Props)
        UNITY_INSTANCING_BUFFER_END(Props)

		struct Input {
			float2 uv_MainTex;
		};
        	
		float4 _Color;
		float _Metallic, _Glossiness;
		sampler2D _MainTex;

		void surf(Input IN, inout SurfaceOutputStandard o) {
			fixed4 c = tex2D(_MainTex, IN.uv_MainTex) * _Color;
			if(c.a < 0.5) discard;
			o.Albedo = c.rgb;
			o.Metallic = _Metallic;
			o.Smoothness = _Glossiness;
			o.Alpha = c.a;
		}
		ENDCG

		// ray tracing pass
		Pass {
			Name "DxrPass"
			Tags { "LightMode" = "DxrPass" }

			HLSLPROGRAM

			#pragma raytracing test
					   
			#include "Common.cginc"

			float4 _Color;
			float _Metallic, _Glossiness;
			Texture2D _MainTex;
			SamplerState sampler_MainTex;

			int _StartDepth;

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				
				rayPayload.distance = RayTCurrent();
				
				// stop if we have reached max recursion depth
				if(rayPayload.depth + 1 == gMaxDepth) {
					return;
				}

				// compute vertex data on ray/triangle intersection
				IntersectionVertex vertex;
				GetCurrentIntersectionVertex(attributeData, vertex);

				// transform normal to world space
				float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
				float3 worldNormal = normalize(mul(objectToWorld, vertex.normalOS));
								
				float3 rayOrigin = WorldRayOrigin();
				float3 rayDir = WorldRayDirection();
				// get intersection world position
				float3 worldPos = rayOrigin + RayTCurrent() * rayDir;

				// get random vector
				float3 randomVector;int i=0;
				do {
					randomVector = float3(nextRand(rayPayload.randomSeed),nextRand(rayPayload.randomSeed),nextRand(rayPayload.randomSeed)) * 2-1;
				} while(i++ < 10 && dot(randomVector,randomVector) > 1.0);

				// get random scattered ray dir along surface normal				
				float3 scatterRayDir = normalize(worldNormal + randomVector);
				// perturb reflection direction to get rought metal effect 
				float3 reflection = normalize(reflect(rayDir, worldNormal) + (1.0 - _Glossiness) * randomVector);
				if(_Metallic > nextRand(rayPayload.randomSeed)) scatterRayDir = reflection;

				RayDesc rayDesc;
				rayDesc.Origin = worldPos;
				rayDesc.Direction = scatterRayDir;
				rayDesc.TMin = 0.001;
				rayDesc.TMax = 100;

				// Create and init the scattered payload
				RayPayload scatterRayPayload;
				scatterRayPayload.color = float3(0.0, 0.0, 0.0);
				scatterRayPayload.randomSeed = rayPayload.randomSeed;
				scatterRayPayload.depth = rayPayload.depth + 1;				

				// shoot scattered ray
				TraceRay(_RaytracingAccelerationStructure, RAY_FLAG_NONE, RAYTRACING_OPAQUE_FLAG, 0, 1, 0, rayDesc, scatterRayPayload);
				
				float4 color0 = _MainTex.SampleLevel(sampler_MainTex, vertex.texCoord0, 0);
				float3 color = color0.rgb * _Color.rgb;
				rayPayload.color = rayPayload.depth == 0 ? 
					scatterRayPayload.color :
					color * scatterRayPayload.color;
			}

			[shader("anyhit")]
			void AnyHitMain(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				IntersectionVertex vertex;
				GetCurrentIntersectionVertex(attributeData, vertex);
				float alpha = _MainTex.SampleLevel(sampler_MainTex, vertex.texCoord0, 0).a * _Color.a;
				if(alpha < nextRand(rayPayload.randomSeed)) {
					IgnoreHit();
				}
				
				// another possibility:
				// AcceptHitAndEndSearch();
				
			}

			ENDHLSL
		}
	}
}
