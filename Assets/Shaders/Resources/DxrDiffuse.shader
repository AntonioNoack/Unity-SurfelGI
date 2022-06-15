Shader "RayTracing/DxrDiffuse" {
	Properties {
		_Color ("Color", Color) = (1, 1, 1, 1)
		_MainTex ("Albedo", 2D) = "white" { }
		_Metallic ("Metallic", Range(0, 1)) = 0.0
		_Glossiness ("Smoothness", Range(0, 1)) = 0.5
		// [Normal] _DetailNormalMap ("Normal Map", 2D) = "bump" {}
		_DetailNormalMapScale("Scale", Float) = 1.0
		// [Normal] _BumpMap("Normal Map", 2D) = "bump" {}
		_BumpMap("Normal Map", 2D) = "bump" {}
	}
	SubShader {
		
		Tags { "RenderType" = "Opaque" }
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
			o.Albedo = c.rgb;
			o.Metallic = _Metallic;
			o.Smoothness = _Glossiness;
			o.Alpha = 1.0;
		}
		ENDCG

		// ray tracing pass
		Pass {
			Name "DxrPass"
			Tags { "LightMode" = "DxrPass" }

			HLSLPROGRAM

			#pragma raytracing test
					   
			#include "Common.cginc"

			// the naming comes from Unitys default shader

			float4 _Color;
			Texture2D _MainTex;
			SamplerState sampler_MainTex;
			
			float _Metallic;
			Texture2D _MetallicGlossMap;

			float _Glossiness;
			Texture2D _SpecGlossMap;

			float _DetailNormalMapScale;
			Texture2D _DetailNormalMap;
			SamplerState sampler_DetailNormalMap;
			
			// for testing, because _DetailNormalMap is not working
			Texture2D _BumpMap;
			SamplerState sampler_BumpMap;

			// many thanks to CustomPhase on Reddit for suggesting this to me:
			// https://forum.unity.com/threads/runtime-generated-bump-maps-are-not-marked-as-normal-maps.413778/#post-4935776
			// Unpack normal as DXT5nm (1, y, 1, x) or BC5 (x, y, 0, 1)
			// Note neutral texture like "bump" is (0, 0, 1, 1) to work with both plain RGB normal and DXT5nm/BC5
			float3 UnpackNormal(float4 packednormal) {
				packednormal.x *= packednormal.w;
				float3 normal;
				normal.xy = packednormal.xy * 2 - 1;
				// this could be set to 1, idk whether we need full accuracy like this
				normal.z = sqrt(1 - saturate(dot(normal.xy, normal.xy)));
				return normal;
			}

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				// stop if we have reached max recursion depth
				if(rayPayload.depth + 1 == gMaxDepth) {
					return;
				}

				// compute vertex data on ray/triangle intersection
				IntersectionVertex vertex;
				GetCurrentIntersectionVertex(attributeData, vertex);

				float lod = 0;

				// transform normal to world space
				float3x3 objectToWorld = (float3x3) ObjectToWorld3x4();
				float3 objectNormal = normalize(vertex.normalOS);
				float3 objectTangent = normalize(vertex.tangentOS);
				float3 objectBitangent = normalize(cross(objectNormal, objectTangent));
				float3 objectNormal1 = UnpackNormal(_BumpMap.SampleLevel(sampler_BumpMap, vertex.texCoord0, lod));
				float2 objectNormal2 = objectNormal1.xy * _DetailNormalMapScale;
				// done check that the order & signs are correct: looks correct :3
				float3 objectNormal3 = objectNormal * objectNormal1.z + objectTangent * objectNormal2.x + objectBitangent * objectNormal2.y;
				float3 worldNormal = normalize(mul(objectToWorld, objectNormal3));
				
				// todo respect metallic and glossiness maps

				// rayPayload.color = saturate(worldNormal*.5+.5);
				// return;
								
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
				
				float4 color0 = _MainTex.SampleLevel(sampler_MainTex, vertex.texCoord0, lod);
				float3 color = color0.rgb * _Color.rgb;
				rayPayload.color = rayPayload.depth == 0 ? 
					scatterRayPayload.color :
					color * scatterRayPayload.color;
			}

			ENDHLSL
		}
	}
}
