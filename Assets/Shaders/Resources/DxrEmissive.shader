Shader "RayTracing/DxrEmissive" {
	Properties {
		[HDR] _Color ("Color", Color) = (1, 1, 1, 1)
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
				rayPayload.color = _Color.xyz;
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

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {	
				// emissive material, simply return emission color
				rayPayload.color = _Color.xyz;		
			}			

			ENDHLSL
		}
	}
}
