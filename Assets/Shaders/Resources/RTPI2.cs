using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using System.Collections.Generic;

public class RTPI2 : MonoBehaviour {

    public RayTracingShader rayTracingShader1, rayTracingShader2;
    public ComputeShader testPass3Shader;

    public Material proceduralMaterial;

    public RayTracingAccelerationStructure surfelRTAS, sceneRTAS;

    private MaterialPropertyBlock properties;

    private GraphicsBuffer aabbList;

    public struct AABB {
        public Vector3 min;
        public Vector3 max;
    };

    private void ReleaseResources() {

        if (surfelRTAS != null) {
            surfelRTAS.Release();
            surfelRTAS = null;
        }

        if (aabbList != null) {
            aabbList.Release();
            aabbList = null;
        }

    }

    public float lightSampleStrength = 1f;
    public float lightAccuArea = 1f;

    private void CreateResources() {

        if (surfelRTAS == null) {
            RayTracingAccelerationStructure.RASSettings settings = new RayTracingAccelerationStructure.RASSettings();
            settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;
            settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Manual;
            settings.layerMask = 255;
            surfelRTAS = new RayTracingAccelerationStructure(settings);
        }

        if (aabbList == null || aabbList.count != surfels.count) {
            aabbList = new GraphicsBuffer(GraphicsBuffer.Target.Structured, surfels.count, 6 * sizeof(float));
        }

        if (properties == null) {
            properties = new MaterialPropertyBlock();
        }
    }

    void OnDestroy() {
        ReleaseResources();
    }

    void OnDisable() {
        ReleaseResources();
    }

    private int frameIndex = 0;
    public ComputeShader aabbShader;
    public ComputeShader surfelToAABBShader;

    public ComputeBuffer surfels, triangles;
    private ComputeBuffer samples;

    public bool pass1, pass2, pass3;

    public void RenderImage() {

        CreateResources();

        if (!SystemInfo.supportsRayTracing) {
            Debug.Log("The RayTracing API is not supported by this GPU or by the current graphics API.");
            return;
        } else if (rayTracingShader1 == null || rayTracingShader2 == null) {
            Debug.Log("Please set a RayTracingShader (check Main Camera).");
            return;
        } else if (proceduralMaterial == null) {
            Debug.Log("Please set a Material for procedural AABBs (check Main Camera).");
            return;
        } else if (surfelRTAS == null || surfelToAABBShader == null || surfels == null)
            return;

        {
            var shader = surfelToAABBShader;
            shader.SetBuffer(0, "_AABBs", aabbList);
            shader.SetBuffer(0, "_Surfels", surfels);
            DXRCamera.Dispatch(shader, 0, Mathf.Min(aabbList.count, surfels.count), 1, 1);
        }
        
        properties.SetBuffer("g_AABBs", aabbList);
        properties.SetBuffer("g_Surfels", surfels);

        surfelRTAS.ClearInstances();
        surfelRTAS.AddInstance(aabbList, (uint) surfels.count, true, Matrix4x4.identity, proceduralMaterial, false, properties);
        surfelRTAS.Build();

        // there cannot be 2 RTAS in the same shader, because of a bug, so we
        // save the intermediate values into a buffer, and use them in a second pass
        if(samples == null || samples.count != surfels.count){
            if(samples != null) samples.Release();
            samples = new ComputeBuffer(surfels.count, 10 * 4);    
        }

        // this is just a random index, and probably should be renamed
        frameIndex++;

        if(
            surfels == null || samples == null || triangles == null || 
            surfelRTAS == null || sceneRTAS == null ||
            rayTracingShader1 == null || rayTracingShader2 == null || testPass3Shader == null
        ) {
            Debug.Log("Sth is null");
            return;
        }

        {
            var shader = rayTracingShader1;
            shader.SetShaderPass("Test");
            shader.SetAccelerationStructure("_RaytracingAccelerationStructure", sceneRTAS);
            shader.SetBuffer("g_Surfels", surfels);
            shader.SetBuffer("g_Samples", samples);
            shader.SetBuffer("g_Triangles", triangles);
            shader.SetInt("_FrameIndex", frameIndex);
            shader.SetFloat("_LightAccuArea", lightAccuArea);
            if(pass1) shader.Dispatch("TestPass1", surfels.count, 1, 1);

            shader = rayTracingShader2;
            shader.SetShaderPass("Test");
            shader.SetAccelerationStructure("_RaytracingAccelerationStructure", surfelRTAS);
            shader.SetBuffer("g_Surfels", surfels);
            shader.SetBuffer("g_Samples", samples);
            shader.SetBuffer("g_Triangles", triangles);
            shader.SetInt("_FrameIndex", frameIndex);
            shader.SetFloat("_Strength", lightSampleStrength);
            if(pass2) shader.Dispatch("TestPass2", surfels.count, 1, 1);
        }

        {
            var shader = testPass3Shader;
            int kernel = shader.FindKernel("AddLightSampleWeights");
            shader.SetBuffer(kernel, "g_Surfels", surfels);
            shader.SetFloat("_DeltaWeight", 1f);
            if(pass3) DXRCamera.Dispatch(shader, kernel, surfels.count, 1, 1);
        }

    }

}
