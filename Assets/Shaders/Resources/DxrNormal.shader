Shader "RayTracing/DxrNormal" {
	Properties {}
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

			[shader("closesthit")]
			void ClosestHit(inout RayPayload rayPayload : SV_RayPayload, AttributeData attributeData : SV_IntersectionAttributes) {
				
				// compute vertex data on ray/triangle intersection
				IntersectionVertex currentvertex;
				GetCurrentIntersectionVertex(attributeData, currentvertex);

				// transform normal to world space
				float3x3 objectToWorld = (float3x3)ObjectToWorld3x4();
				float3 worldNormal = normalize(mul(objectToWorld, currentvertex.normalOS));

				rayPayload.color = worldNormal * 0.5 + 0.5;
			}			

			ENDHLSL
		}
	}
}
