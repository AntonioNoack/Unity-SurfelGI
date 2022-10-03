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
		_EnableLSRT("Enable LSRT", Range(0, 1)) = 0.0
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
					   
			#include "RTLib.cginc"
			#include "Distribution.cginc"

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
			void DxrDiffuseClosest(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				
				rayPayload.distance = RayTCurrent();

				// stop if we have reached max recursion depth
				/*if(rayPayload.depth + 1 >= gMaxDepth) {
					return;
				}*/

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
				float roughness = 1.0 - _Glossiness;
				float3 reflectDir = reflect(rayDir, worldNormal);
				float3 reflection = normalize(reflectDir + roughness * randomVector);
				if(_Metallic > nextRand(rayPayload.randomSeed)) scatterRayDir = reflection;

				float wiCosTheta = abs(dot(rayDir, worldNormal));

				rayPayload.pos = worldPos;
				rayPayload.dir = scatterRayDir;

				// occlusion by surface
				if(dot(scatterRayDir, surfaceWorldNormal) < 0.0){
					rayPayload.dir = 0;
				}

				float4 color = _MainTex.SampleLevel(sampler_MainTex, vertex.texCoord0, lod) * _Color;
				if(rayPayload.depth > 0){
					rayPayload.color *= color;
				}

				// todo define GPT material parameters
				// todo we need materials, that are customized to Mitsuba...

				// todo for sampling:
				// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/libcore/warp.cpp

				// microfacet distribution; visible = true (distr of visible normals)
				// there are multiple types... which one do we choose? Beckmann, GGX, Phong
				// alphaU, alphaV = roughnesses in tangent and bitangent direction
				// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/microfacet.h

				MicrofacetType type = Beckmann;
				float alphaU = roughness, alphaV = roughness;
				float exponentU = 0, exponentV = exponentU; // used by Phong model

				float3 wi = 0;// todo transform rayDir into local space
				float cosThetaWi = abs(dot(rayDir, worldNormal));
				if(_Metallic > 0.5){
					// conductor
					float eta = 1.5;
					float k = 0.0;
					if(roughness > 0.001) {
						// todo replace with rough conductor
						rayPayload.bsdf.components[0].type = EGlossyReflection;
						rayPayload.bsdf.components[0].roughness = 0;// this is not specified...
						float3 H = normalize(rayPayload.queriedWo+wi);
						
						float D = distrEval(type, alphaU, alphaV, exponentU, exponentV, H);
						if(D == 0){
							rayPayload.bsdf.color = 0;
						} else {
							// fresnel factor
							float3 F = fresnelConductorExact(dot(wi, H), eta, k) * color;
							// shadow masking
							float G = distrG(type, alphaU, alphaV, wi, rayPayload.queriedWo, H);
							// total amount of reflection
							float model = D * G / (4.0 * wiCosTheta);
							rayPayload.bsdf.color = F * model;
						}
						rayPayload.bsdf.pdf = distrEval(type, alphaU, alphaV, exponentU, exponentV, H) * distrSmithG1(type, alphaU, alphaV, wi, H) / (4.0 * cosThetaWi);
						rayPayload.bsdf.numComponents = 1;
						// generate random sample
						float pdf;
						float3 m = distrSample(type, alphaU, alphaV, exponentU, exponentV, wi, rayPayload.seed, pdf);
						rayPayload.bsdf.sampledWo = reflectDir;
						rayPayload.bsdf.eta = 1.0;
						rayPayload.bsdf.sampledType = EGlossyReflection;
						float weight = distrSmithG1(type, alphaU, alphaV, reflectDir, m);
						if(weight > 0) {
							rayPayload.bsdf.sampledPdf = pdf / (4.0 * dot(rayPayload.bsdf.sampledWo, m));
							rayPayload.bsdf.sampledColor = pdf * color * fresnelConductorExact(dot(wi, m), eta, k);
						} else {
							rayPayload.bsdf.sampledColor = 0;
							rayPayload.bsdf.sampledPdf = 0;
						}
					} else {
						// perfectly smooth conductor
						// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/conductor.cpp
						rayPayload.bsdf.components[0].type = EDeltaReflection;
						rayPayload.bsdf.components[0].roughness = 0;// this is not specified...
						float eta = 1.5;
						float k = 0.0;
						rayPayload.bsdf.color = color * fresnelConductorExact(cosThetaWi, eta, k);
						rayPayload.bsdf.pdf = abs(dot(reflectDir, rayPayload.queriedWo)-1.0) < 0.01 ? 1.0 : 0.0; // set pdf to 0 if dir != reflectDir
						rayPayload.bsdf.numComponents = 1;
						// generate random sample
						rayPayload.bsdf.sampledType = EDeltaReflection;
						rayPayload.bsdf.sampledWo = reflectDir;
						rayPayload.bsdf.sampledPdf = 1.0;
						rayPayload.bsdf.sampledColor = color * fresnelConductorExact(cosThetaWi, eta, k);
						rayPayload.bsdf.eta = 1.0;
					}
				} else {
					// todo diffuse or plastic material
					rayPayload.bsdf.numComponents = 2;
				}

			}

			ENDHLSL
		}

		// reverse ray tracing: light -> surfels
		Pass {
			Name "Test"
			Tags { "LightMode" = "Test" }

			HLSLPROGRAM

			#pragma raytracing test
			
			#include "RTLib.cginc"

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
			float3 _CameraPos;

			float _EnableLSRT;

			float bdrfDensityB(float dot, float roughness) {// basic bdrf density: how likely a ray it to hit with that normal on that surface roughness
				// abs(d)*d is used instead of d*d to give backside-rays 0 probability
				float r2 = max(roughness * roughness, 1e-10f);// max to avoid division by zero
				return saturate(1.0 + (abs(dot) * dot - 1.0) / r2);
			}

			float bdrfDensityR(float dot) {// brdf density without roughness: how likely a ray it to hit on that normal
				return max(abs(dot) * dot, 0.0);
			}

			[shader("closesthit")]
			void DxrDiffuseClosest2(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				
				rayPayload.distance = RayTCurrent();

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

				
				float3 rayOrigin = WorldRayOrigin();
				float3 rayDir = WorldRayDirection();
				float3 worldPos = rayOrigin + RayTCurrent() * rayDir;
				
				// todo respect metallic and glossiness maps
				bool isMetallic = _Metallic > nextRand(rayPayload.randomSeed);
				float roughness = (1.0 - _Glossiness);
				float3 reflectDir = reflect(rayDir, worldNormal);
				float3 scatterBaseDir = isMetallic ? reflectDir : worldNormal;


				// get intersection world position
				float3 cameraDir = normalize(_CameraPos - worldPos);
				float hittingCameraProbability = lerp(
					bdrfDensityR(dot(worldNormal, cameraDir)),
					bdrfDensityB(dot(reflectDir, cameraDir), roughness),
					_Metallic
				); // can we mix probabilities? should work fine :)

				int remainingDepth = gMaxDepth - rayPayload.depth;
				if(remainingDepth <= 1 || nextRand(rayPayload.randomSeed) * remainingDepth < 1.0) {
					// we cannot trace rays on different RTAS here, because we cannot set it :/
					// save all info into rayPayload, and read it from original sender

					// here we could send an additional ray towards the sky, to sample it better

					rayPayload.weight *= hittingCameraProbability;
					rayPayload.pos = worldPos;
					rayPayload.dir = cameraDir;
					rayPayload.depth = 0xffff;
					return;
				}
				
				// trace into scene, according to probability distribution at surface
				if(remainingDepth <= 1) return;

				// get random vector
				float3 randomVector;int i=0;
				do {
					randomVector = float3(nextRand(rayPayload.randomSeed),nextRand(rayPayload.randomSeed),nextRand(rayPayload.randomSeed)) * 2-1;
				} while(i++ < 10 && dot(randomVector,randomVector) > 1.0);

				// get random scattered ray dir along surface normal
				// perturb reflection direction to get rought metal effect
				float3 scatterRayDir = normalize(scatterBaseDir + (isMetallic ? roughness : 1.0) * randomVector);

				// prevent a lot of light bleeding
				// ambient occlusion, directly by the surface itself
				if(dot(scatterRayDir, surfaceWorldNormal) < 0.0) {
					// do we need to register this zero weight (color = 0) into the surfels?
					// this path is illegal, and therefore just not in path space...
					// mmh..
					rayPayload.weight = 0.0;
					return;
				}

				RayDesc rayDesc;
				rayDesc.Origin = worldPos;
				rayDesc.Direction = scatterRayDir;
				rayDesc.TMin = 0.01;
				rayDesc.TMax = 1000.0;

				rayPayload.depth++;
				
				float4 color0 = _MainTex.SampleLevel(sampler_MainTex, vertex.texCoord0, lod);
				float3 color = color0.rgb * _Color.rgb;
				rayPayload.color *= color;

				// shoot scattered ray
				// rayPayload.withinGlassDepth > 0 ? RAY_FLAG_NONE : RAY_FLAG_CULL_BACK_FACING_TRIANGLES,
				TraceRay(_RaytracingAccelerationStructure, RAY_FLAG_NONE, RAYTRACING_OPAQUE_FLAG, 0, 1, 0, rayDesc, rayPayload);

				// todo differentials...

			}

			ENDHLSL
		}
	}
}
