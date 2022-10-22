Shader "RayTracing/DxrDiffuse" {
	Properties {
		_Color ("Color", Color) = (1, 1, 1, 1)
		_MainTex ("Albedo", 2D) = "white" { }
		_Metallic ("Metallic (white)", Range(0, 1)) = 0.0
		_Metallic2 ("Metallic (black)", Range(0, 1)) = 0.0
		_MetallicGlossMap ("Metallic Mask", 2D) = "white" {}
		_Glossiness ("Smoothness (white)", Range(0, 1)) = 0.5
		_Glossiness2 ("Smoothness (black)", Range(0, 1)) = 0.0
		_SpecGlossMap ("Smoothness Mask", 2D) = "white" {}
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
			float2 uv_MetallicGlossMap;
			float2 uv_SpecGlossMap;
		};
        
		float4 _Color;
		float _Metallic, _Glossiness;
		float _Metallic2, _Glossiness2;
		sampler2D _MainTex;
		sampler2D _MetallicGlossMap;
		sampler2D _SpecGlossMap;

		void surf(Input IN, inout SurfaceOutputStandard o) {
			o.Albedo = (tex2D(_MainTex, IN.uv_MainTex) * _Color).xyz;
			o.Metallic = lerp(_Metallic2, _Metallic, tex2D(_MetallicGlossMap, IN.uv_MetallicGlossMap).x);
			o.Smoothness = lerp(_Glossiness2, _Glossiness, tex2D(_SpecGlossMap, IN.uv_SpecGlossMap).x);
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
			float4 _MainTex_ST;
			SamplerState sampler_MainTex;

			#define GetColor() _MainTex.SampleLevel(sampler_MainTex, TRANSFORM_TEX(vertex.texCoord0, _MainTex), lod) * _Color
			// #define GetColor() float4(frac(TRANSFORM_TEX(vertex.texCoord0, _MetallicGlossMap)), 0.0, 1.0)

			#include "DXRDiffuse.cginc"

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

				// to do we can compute the lod for the first hit, use it
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
				
				// to do respect metallic and glossiness maps
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

				float3 randomVector = nextRandS3(rayPayload.randomSeed);

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
