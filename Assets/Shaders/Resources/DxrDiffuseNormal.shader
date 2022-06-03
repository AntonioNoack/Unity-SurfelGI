Shader "RayTracing/DxrDiffuseNormal" {
	Properties {
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
			#include "UnityCG.cginc"
			struct appdata {
				float4 vertex : POSITION;
				float3 normal : NORMAL;
			};
			struct v2f {
				float4 vertex : SV_POSITION;
				float3 normal : NORMAL;
			};
			v2f vert(appdata v) {
				v2f o;
				o.vertex = UnityObjectToClipPos(v.vertex);
				o.normal = UnityObjectToWorldDir(v.normal);
				return o;
			}
			fixed4 frag(v2f i) : SV_Target {
				return fixed4(i.normal * 0.5 + 0.5, 1.0);
			}
			ENDCG
		}

		// ray tracing pass
		Pass {
			Name "DxrPass"
			Tags { "LightMode" = "DxrPass" }

			HLSLPROGRAM

			#pragma raytracing test
					   
			#include "Common.cginc"

			int _StartDepth;

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

				// get random scattered ray dir along surface normal				
				float3 scatterRayDir = normalize(worldNormal + randomVector);
				float3 _Color = worldNormal * 0.5 + 0.5;

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
				
				rayPayload.color = rayPayload.depth < _StartDepth ? 
					scatterRayPayload.color :
					_Color * scatterRayPayload.color;
			}			

			ENDHLSL
		}
	}
}
