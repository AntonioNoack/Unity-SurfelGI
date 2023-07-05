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

			bool IsOk(float c){
				return c > -1.1 && c < +1.1;
			}

			bool IsOK(float3 c){
				return IsOK(c.x) && IsOK(c.y) && IsOK(c.z);
			}

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
				float3 objectBitangent = normalize(cross(objectTangent, objectNormal));
				float3 objectNormal1 = UnpackNormal(_BumpMap.SampleLevel(sampler_BumpMap, TRANSFORM_TEX(vertex.texCoord0, _BumpMap), lod));
				float2 objectNormal2 = objectNormal1.xy * _DetailNormalMapScale;
				// done check that the order & signs are correct: looks correct :3
				float3 objectNormal3 = objectNormal * objectNormal1.z + objectTangent * objectNormal2.x + objectBitangent * objectNormal2.y;
				float3 worldNormal = normalize(mul(objectToWorld, objectNormal3));
				float3 surfaceWorldNormal = normalize(mul(objectToWorld, vertex.geoNormalOS));
				worldNormal = IsOK(worldNormal) ? worldNormal : normalize(mul(objectToWorld,  objectNormal));
				// worldNormal = surfaceWorldNormal; // set this to make every mesh look flat-shaded
				
				float3 rayOrigin = WorldRayOrigin();
				float3 rayDir = WorldRayDirection();

				rayPayload.pos = rayOrigin + RayTCurrent() * rayDir;

				float roughness = GetRoughness(); // 1.0 - _Glossiness
				float metallic = GetMetallic(); // _Metallic

				// get random vector
				float3 randomVector = nextRandS3(rayPayload.randomSeed);

				// get random scattered ray dir along surface normal
				float3 scatterRayDir = worldNormal + roughness * randomVector;
					
				// perturb reflection direction to get rought metal effect
				if(metallic > nextRand(rayPayload.randomSeed)) {
					scatterRayDir = reflect(rayDir, worldNormal) + roughness * randomVector;
				}
				scatterRayDir = normalize(scatterRayDir);
				rayPayload.dir = scatterRayDir;

				// occlusion by surface
				if(dot(scatterRayDir, surfaceWorldNormal) <= 0.0){
					rayPayload.dir = 0;
					rayPayload.color = 0;
				}
				
				if(rayPayload.depth > 0) {
					float4 color = GetColor();
					rayPayload.color *= color.rgb;
				}

			}

#endif // DXRDIFFUSE_CGING