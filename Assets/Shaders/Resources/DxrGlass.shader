Shader "RayTracing/DxrGlass" {
	Properties {
		_Color ("Color", Color) = (1, 1, 1, 1)
		_Roughness ("Roughness", Range(0, 1)) = 0.5
		_IoR ("IoR", Range(0, 5)) = 1.5
		_StartDepth("Start Depth", Int) = 0
	}
	SubShader {
		Tags { "RenderType"="Opaque" }
		LOD 100

		// basic rasterization pass that will allow us to see the material in SceneView
		Pass {
			CGPROGRAM
			#pragma vertex vert
			#pragma fragment frag
			#include "SimpleLit.cginc"
			ENDCG
		}
		
		// color pass
		Pass {
			Name "ColorPass"
			Tags { "LightMode" = "ColorPass" }

			HLSLPROGRAM

			#pragma raytracing test
					   
			#include "Common.cginc"

			float4 _Color;

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				rayPayload.color = _Color;
			}
			ENDHLSL
		}

		// normal pass
		Pass {
			Name "NormalPass"
			Tags { "LightMode" = "NormalPass" }

			HLSLPROGRAM

			#pragma raytracing test
					   
			#include "Common.cginc"

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				IntersectionVertex currentvertex;
				GetCurrentIntersectionVertex(attributeData, currentvertex);
				float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
				float3 worldNormal = normalize(mul(objectToWorld, currentvertex.normalOS));
				rayPayload.color = worldNormal * 0.5 + 0.5;
			}
			ENDHLSL
		}

		// ray tracing pass
		Pass {
			Name "DxrPass"
			Tags { "LightMode" = "DxrPass" }

			HLSLPROGRAM

			#pragma raytracing test
					   
			#include "Common.cginc"

			float4 _Color;
			float _Roughness;
			float _IoR;
			int _StartDepth;

			float3 ComputeRefractionDirection(float3 rayDir, float3 normal, float ior) {
				// flip normal if we hit back face
				float3 normal2 = (-sign(dot(normal, rayDir))) * normal;
				return refract(rayDir, normal2, ior);
			}

			float FresnelShlick(float cosine, float refractionIndex) {
				// compute fresnel term
				float r0 = (1.0 - refractionIndex) / (1.0 + refractionIndex);
				r0 = r0 * r0;
				return r0 + (1.0 - r0) * pow(1.0 - cosine, 5.0);
			}

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				// stop if we have reached max recursion depth
				if(rayPayload.depth + 1 == gMaxDepth) {
					return;
				}

				// compute vertex data on ray/triangle intersection
				IntersectionVertex currentvertex;
				GetCurrentIntersectionVertex(attributeData, currentvertex);

				// transform normal to world space
				float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
				float3 worldNormal = normalize(mul(objectToWorld, currentvertex.normalOS));

				float3 rayOrigin = WorldRayOrigin();
				float3 rayDir = WorldRayDirection();
				// get intersection world position
				float3 worldPos = rayOrigin + RayTCurrent() * rayDir;

				// get random vector
				float3 randomVector;int i=0;
				do {
					randomVector = float3(nextRand(rayPayload.randomSeed),nextRand(rayPayload.randomSeed),nextRand(rayPayload.randomSeed)) * 2-1;
				} while(i++ < 10 && dot(randomVector,randomVector) > 1.0);

				// get index of refraction (IoR)
				// IoR for front faces = AirIor / MaterialIoR
				// IoR for back faces = MaterialIoR / AirIor
				float currentIoR = dot(rayDir, worldNormal) <= 0.0 ? 1.0 / _IoR : _IoR;
				// flip angle for backfaces
				float cosine = abs(dot(rayDir, worldNormal));

				// get fresnel factor, it will be used as a probability of a refraction (vs reflection)
				float refrProb = FresnelShlick(cosine, currentIoR);
				// compute refraction vector
				float3 refractionDir = ComputeRefractionDirection(rayDir, worldNormal, currentIoR);				

				// change refraction to reflection based on fresnel
				if(nextRand(rayPayload.randomSeed) < refrProb) {
					refractionDir = reflect(rayDir, worldNormal);
				}

				// perturb refraction/reflection to get frosted glass effect
				refractionDir = normalize(refractionDir + randomVector * _Roughness);
								
				RayDesc rayDesc;
				rayDesc.Origin = worldPos;
				rayDesc.Direction = refractionDir;
				rayDesc.TMin = 0.001;
				rayDesc.TMax = 100;

				// Create and init the ray payload
				RayPayload scatterRayPayload;
				scatterRayPayload.color = float3(0.0, 0.0, 0.0);
				scatterRayPayload.randomSeed = rayPayload.randomSeed;
				scatterRayPayload.depth = rayPayload.depth + 1;
				
				// shoot refraction/reflection ray
				TraceRay(_RaytracingAccelerationStructure, RAY_FLAG_NONE, RAYTRACING_OPAQUE_FLAG, 0, 1, 0, rayDesc, scatterRayPayload);
				
				rayPayload.color = rayPayload.depth < _StartDepth ? 
					scatterRayPayload.color :
					_Color * scatterRayPayload.color;
			}

			ENDHLSL
		}
	}
}
