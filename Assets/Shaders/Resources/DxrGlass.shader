Shader "RayTracing/DxrGlass" {
	Properties {
		_Color ("Color", Color) = (1, 1, 1, 1)
		_Roughness ("Roughness", Range(0, 1)) = 0.5
		_IoR ("IoR", Range(0, 5)) = 1.5
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
		float _Roughness;

		void surf(Input IN, inout SurfaceOutputStandard o) {
			fixed4 c = _Color;
			o.Albedo = c.rgb;
			o.Metallic = 1.0;
			o.Smoothness = 1.0 - _Roughness;
			o.Alpha = c.a;
		}
		ENDCG

		// ray tracing pass
		Pass {
			Name "DxrPass"
			Tags { "LightMode" = "DxrPass" }

			HLSLPROGRAM

			#pragma raytracing test
					   
			#include "RTLib.cginc"
			#include "Distribution.cginc"

			float4 _Color;
			float _Roughness;
			float _IoR;

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
				
				rayPayload.distance = RayTCurrent();

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
				bool enteringGlass = dot(rayDir, worldNormal) <= 0.0;
				float currentIoR = enteringGlass ? 1.0 / _IoR : _IoR;
				// flip angle for backfaces
				float cosine = abs(dot(rayDir, worldNormal));

				// get fresnel factor, it will be used as a probability of a refraction (vs reflection)
				float refrProb = FresnelShlick(cosine, currentIoR);
				// compute refraction vector
				float3 refractionDir = ComputeRefractionDirection(rayDir, worldNormal, currentIoR);
				float3 reflectionDir = reflect(rayDir, worldNormal);

				float3 newDir = refractionDir;
				// change refraction to reflection based on fresnel
				if(nextRand(rayPayload.randomSeed) < refrProb) {
					newDir = reflectionDir;
				}

				// perturb refraction/reflection to get frosted glass effect
				newDir = normalize(newDir + randomVector * _Roughness);
				
				rayPayload.withinGlassDepth = max(0, rayPayload.withinGlassDepth + (enteringGlass ? 1 : -1));

				rayPayload.pos = worldPos;
				rayPayload.dir = newDir;

				if(rayPayload.depth > 0) {
					rayPayload.color *= _Color;
				}

				//------------------------//
				// define GPT class BSDF  //
				//      (dielectric)      //
				//------------------------//

				float eta = _IoR;
				rayPayload.bsdf.eta = _IoR;
				rayPayload.bsdf.color = _Color;
				rayPayload.geoFrame = normalToFrame(worldNormal);
				rayPayload.shFrame = rayPayload.geoFrame;

				if(true || _Roughness < 0.01){
					// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/dielectric.cpp
					rayPayload.bsdf.components[0].type = EDeltaReflection;
					rayPayload.bsdf.components[0].roughness = 0.0;
					rayPayload.bsdf.components[1].type = EDeltaTransmission;
					rayPayload.bsdf.components[1].roughness = 0.0;
					rayPayload.bsdf.numComponents = 2;
				} else {
					// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/roughdielectric.cpp
					// todo rough dielectric as well
					// alpha (Beckmann): root mean square slope of microfacets; default: 0.1
					// setting this to _Roughness [0,1] limits the values to a mean (RMS) slope of 45°, but that's probably fine
					rayPayload.bsdf.components[0].roughness = _Roughness; // (alphaU+alphaV)/2
					rayPayload.bsdf.components[0].type = EGlossyReflection;
					rayPayload.bsdf.components[1].roughness = _Roughness;
					rayPayload.bsdf.components[1].type = EGlossyTransmission;
					rayPayload.bsdf.numComponents = 2;
				}

			}

			ENDHLSL
		}
	}
}
