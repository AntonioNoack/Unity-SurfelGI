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

			// for testing, because _DetailNormalMap is not working
			Texture2D _BumpMap;
			SamplerState sampler_BumpMap;
			float _DetailNormalMapScale;

			float _EnableRayDifferentials;

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

				// todo we can compute the lod for the first hit, use it
				float lod = 0;

				// transform normal to world space & apply normal map
				float3x3 objectToWorld = (float3x3) ObjectToWorld3x4();
				float3 objectNormal = normalize(vertex.normalOS);
				float3 objectTangent = normalize(vertex.tangentOS);
				float3 objectBitangent = normalize(cross(objectNormal, objectTangent));
				float3 objectNormal1 = UnpackNormal(_BumpMap.SampleLevel(sampler_BumpMap, vertex.texCoord0, lod));
				float2 objectNormal2 = objectNormal1.xy * _DetailNormalMapScale;
				// done check that the order & signs are correct: looks correct :3
				float3 objectNormal3 = objectNormal * objectNormal1.z + objectTangent * objectNormal2.x + objectBitangent * objectNormal2.y;
				float3 worldNormal = normalize(mul(objectToWorld, objectNormal3));
				float3 surfaceWorldNormal = normalize(mul(objectToWorld, objectNormal));
				
				
				// todo respect metallic and glossiness maps
								
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

				// prevent a lot of light bleeding
				if(dot(scatterRayDir, surfaceWorldNormal) >= 0.0) {

					RayDesc rayDesc;
					rayDesc.Origin = worldPos;
					rayDesc.Direction = scatterRayDir;
					rayDesc.TMin = 0;
					rayDesc.TMax = 1000;

					// Create and init the scattered payload
					RayPayload scatterRayPayload;
					scatterRayPayload.color = float3(0.0, 0.0, 0.0);
					scatterRayPayload.randomSeed = rayPayload.randomSeed;
					scatterRayPayload.depth = rayPayload.depth + 1;	

					// shoot scattered ray
					TraceRay(_RaytracingAccelerationStructure,
						scatterRayPayload.withinGlassDepth > 0 ? RAY_FLAG_NONE : RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
						RAYTRACING_OPAQUE_FLAG, 0, 1, 0, rayDesc, scatterRayPayload);
					
					float4 color0 = _MainTex.SampleLevel(sampler_MainTex, vertex.texCoord0, lod);
					float3 color = color0.rgb * _Color.rgb;
					rayPayload.color = rayPayload.depth == 0 ? 
						scatterRayPayload.color :
						color * scatterRayPayload.color;

					// check if we need to trace ray differentials
					if(_EnableRayDifferentials && rayPayload.depth == 0){

						float distanceToNextSurface = scatterRayPayload.distance;
						float3 nextSurfacePos = worldPos + distanceToNextSurface * scatterRayDir;

						// todo generate both ray starting points and directions
						// todo calculate actual gradient values

						float baseAngle = TAU * nextRand(rayPayload.randomSeed);
						float2 baseSinCos = float2(sin(baseAngle), cos(baseAngle));
						float4 surfelRotation = float4(0,0,0,1);// todo get this value
						float surfelSize = 1.0;// todo get this value
						float distance = surfelSize * lerp(0.01, 1.0, nextRand(rayPayload.randomSeed));

						float3 baseX = quatRot(float3(1,0,0), surfelRotation);
						float3 baseZ = quatRot(float3(0,0,1), surfelRotation);
						float3 ray1Pos = worldPos + baseSinCos.x * baseX + baseSinCos.y * baseZ;
						float3 ray2Pos = worldPos + baseSinCos.y * baseX - baseSinCos.x * baseZ;

						
						// todo only check for surface properties and visibility at that location,
						// todo perhaps with some kind of flag

						/**
						 * trace differential ray 1
						 */
						rayDesc.Origin = ray1Pos;
						float3 deltaPos1 = nextSurfacePos - ray1Pos;
						float deltaLen1 = length(deltaPos1);
						rayDesc.Direction = deltaPos1 / deltaLen1;
						rayDesc.TMin = 0;
						rayDesc.TMax = deltaLen1 * 1.01;

						RayPayload scatterRayPayload1;
						scatterRayPayload1.color = float3(0.0, 0.0, 0.0);
						scatterRayPayload1.randomSeed = rayPayload.randomSeed;
						scatterRayPayload1.depth = 0x1000;
						scatterRayPayload1.withinGlassDepth = rayPayload.withinGlassDepth;

						TraceRay(_RaytracingAccelerationStructure,
							scatterRayPayload1.withinGlassDepth > 0 ? RAY_FLAG_NONE : RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
							RAYTRACING_OPAQUE_FLAG, 0, 1, 0, rayDesc, scatterRayPayload1);

						/**
						 * trace differential ray 2
						 */
						rayDesc.Origin = ray2Pos;
						float3 deltaPos2 = nextSurfacePos - ray1Pos;
						float deltaLen2 = length(deltaPos2);
						rayDesc.Direction = deltaPos2 / deltaLen2;
						rayDesc.TMin = 0;
						rayDesc.TMax = deltaLen2 * 1.01;
						
						RayPayload scatterRayPayload2;
						scatterRayPayload2.color = float3(0.0, 0.0, 0.0);
						scatterRayPayload2.randomSeed = rayPayload.randomSeed;
						scatterRayPayload2.depth = 0x1000;
						scatterRayPayload2.withinGlassDepth = rayPayload.withinGlassDepth;

						TraceRay(_RaytracingAccelerationStructure, 
							scatterRayPayload2.withinGlassDepth > 0 ? RAY_FLAG_NONE : RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
							RAYTRACING_OPAQUE_FLAG, 0, 1, 0, rayDesc, scatterRayPayload2);

						// todo check if those rays have hit the target

						// todo trace two rays to find these
						float4 value1 = 0;
						float4 value2 = 0;

						// should be correct
						float3 value0 = scatterRayPayload.color;

						float3 gradient1 = (value1 - value0) / distance;// store it relative to surfel size?
						float3 gradient2 = (value2 - value0) / distance;

						float3 gradientDX = baseSinCos.x; // todo reverse rotation
						float3 gradientDY = baseSinCos.y;

					}
					
				} // else ambient occlusion, directly by the surface itself

				
			}

			ENDHLSL
		}

		// reverse ray tracing: light -> surfels
		Pass {
			Name "DxrPass2"
			Tags { "LightMode" = "DxrPass2" }

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
			
			Texture2D _BumpMap;
			SamplerState sampler_BumpMap;
			float _DetailNormalMapScale;

			float _EnableRayDifferentials;

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				
				rayPayload.distance = RayTCurrent();

				int remainingDepth = gMaxDepth - rayPayload.depth;
				if(remainingDepth <= 1 || nextRand(rayPayload.randomSeed) * remainingDepth < 1.0) {

					// todo trace towards camera
					// todo cancel iteration, and return: position + color incl. probability
					IntersectionVertex vertex;
					GetCurrentIntersectionVertex(attributeData, vertex);
					
					float4x3 objectToWorld = ObjectToWorld4x3();
					float3 posWS = mul(objectToWorld, float4(vertex.positionOS, 1));

					// only relevant, if we are using no acceleration structure for the surfels
					// to do calculate UVs -> if we are behind the camera, we don't even need to try, because we cannot save the information


					// todo calculate probability, and best multiply it above to waste less rays


					// todo if hit, return
					return;
				}

				if(remainingDepth <= 1) {
					return;
				}

				// todo trace into scene, according to probability distribution at surface
				

				// stop if we have reached max recursion depth
				if(rayPayload.depth + 1 == gMaxDepth) {
					return;
				}

				// compute vertex data on ray/triangle intersection
				IntersectionVertex vertex;
				GetCurrentIntersectionVertex(attributeData, vertex);

				// todo we can compute the lod for the first hit, use it
				float lod = 0;

				// transform normal to world space & apply normal map
				float3x3 objectToWorld = (float3x3) ObjectToWorld3x4();
				float3 objectNormal = normalize(vertex.normalOS);
				float3 objectTangent = normalize(vertex.tangentOS);
				float3 objectBitangent = normalize(cross(objectNormal, objectTangent));
				float3 objectNormal1 = UnpackNormal(_BumpMap.SampleLevel(sampler_BumpMap, vertex.texCoord0, lod));
				float2 objectNormal2 = objectNormal1.xy * _DetailNormalMapScale;
				// done check that the order & signs are correct: looks correct :3
				float3 objectNormal3 = objectNormal * objectNormal1.z + objectTangent * objectNormal2.x + objectBitangent * objectNormal2.y;
				float3 worldNormal = normalize(mul(objectToWorld, objectNormal3));
				float3 surfaceWorldNormal = normalize(mul(objectToWorld, objectNormal));
				
				// todo respect metallic and glossiness maps

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

				// prevent a lot of light bleeding
				if(dot(scatterRayDir, surfaceWorldNormal) >= 0.0) {
					
					RayDesc rayDesc;
					rayDesc.Origin = worldPos;
					rayDesc.Direction = scatterRayDir;
					rayDesc.TMin = 0;
					rayDesc.TMax = 1000;

					// Create and init the scattered payload
					RayPayload scatterRayPayload;
					scatterRayPayload.color = float3(0.0, 0.0, 0.0);
					scatterRayPayload.randomSeed = rayPayload.randomSeed;
					scatterRayPayload.depth = rayPayload.depth + 1;	

					// shoot scattered ray
					TraceRay(_RaytracingAccelerationStructure,
						scatterRayPayload.withinGlassDepth > 0 ? RAY_FLAG_NONE : RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
						RAYTRACING_OPAQUE_FLAG, 0, 1, 0, rayDesc, scatterRayPayload);
					
					float4 color0 = _MainTex.SampleLevel(sampler_MainTex, vertex.texCoord0, lod);
					float3 color = color0.rgb * _Color.rgb;
					rayPayload.color = rayPayload.depth == 0 ? 
						scatterRayPayload.color :
						color * scatterRayPayload.color;

					// todo differentials...

				} // else ambient occlusion, directly by the surface itself

				
			}

			ENDHLSL
		}
	}
}
