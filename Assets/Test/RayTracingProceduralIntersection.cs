using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using System.Collections.Generic;

[ExecuteInEditMode]
public class RayTracingProceduralIntersection : MonoBehaviour {

    public RayTracingShader rayTracingShader = null;

    public Material proceduralMaterial = null;

    private uint cameraWidth = 0;
    private uint cameraHeight = 0;

    private RenderTexture rayTracingOutput = null;

    private RayTracingAccelerationStructure raytracingAccelerationStructure = null;

    private MaterialPropertyBlock properties = null;

    private GraphicsBuffer aabbList = null;
    private GraphicsBuffer aabbColors = null;

    public int aabbCount = 10;

    public struct AABB {
        public Vector3 min;
        public Vector3 max;
    }

    private void CreateRaytracingAccelerationStructure() {
        if (raytracingAccelerationStructure == null) {
            RayTracingAccelerationStructure.RASSettings settings = new RayTracingAccelerationStructure.RASSettings();
            settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;
            settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Manual;
            settings.layerMask = 255;

            raytracingAccelerationStructure = new RayTracingAccelerationStructure(settings);
        }
    }

    private void ReleaseResources() {
        if (raytracingAccelerationStructure != null) {
            raytracingAccelerationStructure.Release();
            raytracingAccelerationStructure = null;
        }

        if (rayTracingOutput) {
            rayTracingOutput.Release();
            rayTracingOutput = null;
        }

        if (aabbList != null) {
            aabbList.Release();
            aabbList = null;
        }

        if (aabbColors != null) {
            aabbColors.Release();
            aabbColors = null;
        }

        cameraWidth = 0;
        cameraHeight = 0;
    }

    private void CreateResources() {
        CreateRaytracingAccelerationStructure();

        if (cameraWidth != Camera.main.pixelWidth || cameraHeight != Camera.main.pixelHeight) {
            if (rayTracingOutput)
                rayTracingOutput.Release();

            rayTracingOutput = new RenderTexture(Camera.main.pixelWidth, Camera.main.pixelHeight, 0, RenderTextureFormat.ARGBHalf);
            rayTracingOutput.enableRandomWrite = true;
            rayTracingOutput.Create();

            cameraWidth = (uint)Camera.main.pixelWidth;
            cameraHeight = (uint)Camera.main.pixelHeight;
        }

        if (aabbList == null || aabbList.count != aabbCount) {
            aabbList = new GraphicsBuffer(GraphicsBuffer.Target.Structured, aabbCount, 6 * sizeof(float));
            /*AABB[] aabbs = new AABB[aabbCount];
            for (int i = 0; i < aabbCount; i++) {
                AABB aabb = new AABB();
                Vector3 center = new Vector3(-4 + 8 * (float)i / (float)(aabbCount - 1), 0, 4);
                Vector3 size = new Vector3(0.2f, 6.0f, 0.2f);
                aabb.min = center - size;
                aabb.max = center + size;
                aabbs[i] = aabb;
            }
            aabbList.SetData(aabbs);*/
        }

        if (aabbColors == null || aabbColors.count != aabbCount) {
            aabbColors = new GraphicsBuffer(GraphicsBuffer.Target.Structured, aabbCount, 4 * sizeof(float));
            Color[] colors = new Color[aabbCount];
            for (int i = 0; i < aabbCount; i++) {
                colors[i] = new Vector4(1.0f - (i / (float)(aabbCount - 1)), i / (float)(aabbCount - 1), 0, 1);
            }
            aabbColors.SetData(colors);
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

    private void Update() {
        CreateResources();
    }

    private float time = 0;
    public ComputeShader aabbShader;
    public ComputeShader surfelToAABBShader;

    // todo let this be defined by DXRCamera
    public ComputeBuffer surfels;

    public bool hasSurfels = false, hasUpdate = false;
    public bool preferUpdate = true;

    [ImageEffectOpaque]
    void OnRenderImage(RenderTexture src, RenderTexture dest) {
        if (!SystemInfo.supportsRayTracing) {
            Debug.Log("The RayTracing API is not supported by this GPU or by the current graphics API.");
            Graphics.Blit(src, dest);
            return;
        } else if (rayTracingShader == null) {
            Debug.Log("Please set a RayTracingShader (check Main Camera).");
            Graphics.Blit(src, dest);
            return;
        } else if (proceduralMaterial == null) {
            Debug.Log("Please set a Material for procedural AABBs (check Main Camera).");
            Graphics.Blit(src, dest);
            return;
        } else if (raytracingAccelerationStructure == null)
            return;

        CommandBuffer cmdBuffer = null;new CommandBuffer();

        raytracingAccelerationStructure.ClearInstances();

        /*List<Material> materials = new List<Material>();
        MeshRenderer[] renderers = FindObjectsOfType<MeshRenderer>();
        foreach (MeshRenderer r in renderers) {
            r.GetSharedMaterials(materials);

            int matCount = Mathf.Max(materials.Count, 1);

            RayTracingSubMeshFlags[] subMeshFlags = new RayTracingSubMeshFlags[matCount];

            // Assume all materials are opaque (anyhit shader is disabled) otherwise Material types (opaque, transparent) must be handled here.
            for (int i = 0; i < matCount; i++)
                subMeshFlags[i] = RayTracingSubMeshFlags.Enabled | RayTracingSubMeshFlags.ClosestHitOnly;

            raytracingAccelerationStructure.AddInstance(r, subMeshFlags);
        }*/

        properties.SetBuffer("g_AABBs", aabbList);
        properties.SetBuffer("g_Colors", aabbColors);

        hasSurfels = false;
        hasUpdate = false;

        bool updated = false;
        if((surfelToAABBShader != null && surfels != null) && !preferUpdate){
            aabbCount = surfels.count;
            var shader = surfelToAABBShader;
            if(shader != null){
                hasSurfels = true;
                shader.SetBuffer(0, "_AABBs", aabbList);
                shader.SetBuffer(0, "_Surfels", surfels);
                shader.SetVector("_DispatchOffset", new Vector3(0,0,0));
                DXRCamera.Dispatch(shader, 0, Mathf.Min(aabbList.count, surfels.count), 1, 1);
                updated = true;
            }
        } 
        if(!updated) {
            var shader = aabbShader;
            if(shader != null){
                hasUpdate = true;
                shader.SetFloat("_Time", time);
                shader.SetBuffer(0, "_Result", aabbList);
                DXRCamera.Dispatch(shader, 0, aabbList.count, 1, 1);
            }
        }
        
        time += Time.deltaTime;

        // Create a procedural geometry instance based on a AABB list. The GraphicsBuffer contains static data.
        raytracingAccelerationStructure.AddInstance(aabbList, (uint) aabbCount, true, Matrix4x4.identity, proceduralMaterial, false, properties);

        if(cmdBuffer != null) cmdBuffer.BuildRayTracingAccelerationStructure(raytracingAccelerationStructure);
        else raytracingAccelerationStructure.Build();

        if(cmdBuffer != null) cmdBuffer.SetRayTracingShaderPass(rayTracingShader, "Test");
        else rayTracingShader.SetShaderPass("Test");

        // Input
        if(cmdBuffer != null) cmdBuffer.SetRayTracingAccelerationStructure(rayTracingShader, Shader.PropertyToID("g_SceneAccelStruct"), raytracingAccelerationStructure);
        else rayTracingShader.SetAccelerationStructure("g_SceneAccelStruct", raytracingAccelerationStructure);
        if(cmdBuffer != null) cmdBuffer.SetRayTracingMatrixParam(rayTracingShader, Shader.PropertyToID("g_InvViewMatrix"), Camera.main.cameraToWorldMatrix);
        else rayTracingShader.SetMatrix("g_InvViewMatrix", Camera.main.cameraToWorldMatrix);
        if(cmdBuffer != null) cmdBuffer.SetRayTracingFloatParam(rayTracingShader, Shader.PropertyToID("g_Zoom"), Mathf.Tan(Mathf.Deg2Rad * Camera.main.fieldOfView * 0.5f));
        else rayTracingShader.SetFloat("g_Zoom", Mathf.Tan(Mathf.Deg2Rad * Camera.main.fieldOfView * 0.5f));

        // Output
        if(cmdBuffer != null) cmdBuffer.SetRayTracingTextureParam(rayTracingShader, Shader.PropertyToID("g_Output"), rayTracingOutput);
        else rayTracingShader.SetTexture("g_Output", rayTracingOutput);

        if(cmdBuffer != null) cmdBuffer.DispatchRays(rayTracingShader, "MainRayGenShader", cameraWidth, cameraHeight, 1);
        else rayTracingShader.Dispatch("MainRayGenShader", (int) cameraWidth, (int) cameraHeight, 1);

        if(cmdBuffer != null) Graphics.ExecuteCommandBuffer(cmdBuffer);
        if(cmdBuffer != null) cmdBuffer.Release();

        Graphics.Blit(rayTracingOutput, dest);
    }
}
