#ifndef DXRDIFFUSE_CGING
#define DXRDIFFUSE_CGING
			
			float _Metallic, _Metallic2;
			Texture2D _MetallicGlossMap;
			float4 _MetallicGlossMap_ST;
			SamplerState sampler_MetallicGlossMap;

			float _Glossiness, _Glossiness2;
			Texture2D _SpecGlossMap;
			float4 _SpecGlossMap_ST;
			SamplerState sampler_SpecGlossMap;

			#define TRANSFORM_TEX(tex, name) (tex.xy * name##_ST.xy + name##_ST.zw)

			#define GetMetallic() lerp(_Metallic2, _Metallic, _MetallicGlossMap.SampleLevel(sampler_MetallicGlossMap, TRANSFORM_TEX(vertex.texCoord0, _MetallicGlossMap), lod).x)
			#define GetRoughness() 1.0 - lerp(_Glossiness2, _Glossiness, _SpecGlossMap.SampleLevel(sampler_SpecGlossMap, TRANSFORM_TEX(vertex.texCoord0, _SpecGlossMap), lod).x)

			// for testing, because _DetailNormalMap is not working
			Texture2D _BumpMap;
			float4 _BumpMap_ST;
			SamplerState sampler_BumpMap;
			float _DetailNormalMapScale;

			[shader("closesthit")]
			void DxrDiffuseClosest(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				
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
				float3 objectNormal1 = UnpackNormal(_BumpMap.SampleLevel(sampler_BumpMap, TRANSFORM_TEX(vertex.texCoord0, _BumpMap), lod));
				float2 objectNormal2 = objectNormal1.xy * _DetailNormalMapScale;
				// done check that the order & signs are correct: looks correct :3
				float3 objectNormal3 = objectNormal * objectNormal1.z + objectTangent * objectNormal2.x + objectBitangent * objectNormal2.y;
				float3 worldNormal = normalize(mul(objectToWorld, objectNormal3));
				float3 surfaceWorldNormal = normalize(mul(objectToWorld, vertex.geoNormalOS));
				// worldNormal = surfaceWorldNormal; // set this to make every mesh look flat-shaded
				
				// todo respect metallic and glossiness maps
				
				float3 rayOrigin = WorldRayOrigin();
				float3 rayDir = WorldRayDirection();

				rayPayload.pos = rayOrigin + RayTCurrent() * rayDir;

				float roughness = GetRoughness(); // 1.0 - _Glossiness
				float metallic = GetMetallic(); // _Metallic

				if(!rayPayload.gpt){
					// get random vector
					float3 randomVector;int i=0;
					do {
						randomVector = float3(nextRand(rayPayload.randomSeed),nextRand(rayPayload.randomSeed),nextRand(rayPayload.randomSeed)) * 2-1;
					} while(i++ < 10 && dot(randomVector,randomVector) > 1.0);

					// get random scattered ray dir along surface normal
					float3 scatterRayDir = normalize(worldNormal + randomVector);
					// perturb reflection direction to get rought metal effect 
					float3 reflectDir = reflect(rayDir, worldNormal);
					float3 reflection = normalize(reflectDir + roughness * randomVector);
					if(metallic > nextRand(rayPayload.randomSeed)) scatterRayDir = reflection;
					rayPayload.dir = scatterRayDir;

					// occlusion by surface
					if(dot(scatterRayDir, surfaceWorldNormal) < 0.0){
						rayPayload.dir = 0;
					}
				}

				float4 color = GetColor();
				if(!rayPayload.gpt && rayPayload.depth > 0){
					rayPayload.color *= color;
				}

				if(rayPayload.gpt){
					// define GPT material parameters

					// microfacet distribution; visible = true (distr of visible normals)
					// there are multiple types... which one do we choose? Beckmann, GGX, Phong
					// alphaU, alphaV = roughnesses in tangent and bitangent direction
					// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/microfacet.h

					// define geoFrame and shFrame;
					// the function is defined to make y = up, but for Mitsuba, we need z = up, so we swizzle it
					rayPayload.geoFrame = normalToFrame(surfaceWorldNormal);
					rayPayload.shFrame = normalToFrame(worldNormal);

					float alphaU = roughness, alphaV = roughness;
					// what is a good value for the exponent?
					float exponentU = 100.0, exponentV = exponentU; // used by Phong model

					rayPayload.bsdf.roughness = roughness;
					rayPayload.bsdf.color = color;

					if(metallic > nextRand(rayPayload.randomSeed)){
						// metallic, conductor material
						if(roughness > 0.01) {
							// rough conductor
							// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/roughconductor.cpp
							rayPayload.bsdf.components[0].type = EGlossyReflection;
							rayPayload.bsdf.components[0].roughness = 0.0;
							rayPayload.bsdf.numComponents = 1;
							rayPayload.bsdf.materialType = ROUGH_CONDUCTOR;
						} else {
							// perfectly smooth conductor
							// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/conductor.cpp
							rayPayload.bsdf.components[0].type = EDeltaReflection;
							rayPayload.bsdf.components[0].roughness = 0.0;
							rayPayload.bsdf.numComponents = 1;
							rayPayload.bsdf.materialType = CONDUCTOR;
						}
					} else {
						// diffuse material
						if(roughness < 0.01){
							// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/diffuse.cpp
							rayPayload.bsdf.components[0].type = EDiffuseReflection;
							rayPayload.bsdf.components[0].roughness = Infinity;
							rayPayload.bsdf.numComponents = 1;
							rayPayload.bsdf.materialType = ROUGH_DIFFUSE;
						} else {
							// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/roughdiffuse.cpp
							rayPayload.bsdf.components[0].type = EGlossyReflection;
							rayPayload.bsdf.components[0].roughness = Infinity;// why?
							rayPayload.bsdf.numComponents = 1;
							rayPayload.bsdf.materialType = DIFFUSE;
						}
					}
				}
			}

#endif // DXRDIFFUSE_CGING