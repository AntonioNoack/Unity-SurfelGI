using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using System.Collections.Generic;

public class RayTracingProceduralIntersection : MonoBehaviour {

    public RayTracingShader rayTracingShader = null;

    public Material proceduralMaterial = null;

    private uint cameraWidth = 0, cameraHeight = 0;

    private RenderTexture rayTracingOutput = null;

    public RayTracingAccelerationStructure surfelRTAS = null, sceneRTAS = null;

    private MaterialPropertyBlock properties = null;

    private GraphicsBuffer aabbList = null;
    private GraphicsBuffer aabbColors = null;

    public int aabbCount = 10;

    public struct AABB {
        public Vector3 min;
        public Vector3 max;
    }

    private void CreateRaytracingAccelerationStructure() {
        if (surfelRTAS == null) {
            RayTracingAccelerationStructure.RASSettings settings = new RayTracingAccelerationStructure.RASSettings();
            settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;
            settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Manual;
            settings.layerMask = 255;

            surfelRTAS = new RayTracingAccelerationStructure(settings);
        }
    }

    private void ReleaseResources() {
        if (surfelRTAS != null) {
            surfelRTAS.Release();
            surfelRTAS = null;
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

    public ComputeBuffer surfels, triangles;

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
        } else if (surfelRTAS == null)
            return;

        surfelRTAS.ClearInstances();

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
        surfelRTAS.AddInstance(aabbList, (uint) aabbCount, true, Matrix4x4.identity, proceduralMaterial, false, properties);

        surfelRTAS.Build();
        rayTracingShader.SetShaderPass("Test");

        int id1 = Shader.PropertyToID("g_SceneAccelStruct");
        int id2 = Shader.PropertyToID("g_SceneAccelStruct2");

        Debug.Log("Id1/2: "+id1+"/"+id2);

        if(swap){
            rayTracingShader.SetAccelerationStructure("g_SceneAccelStruct", surfelRTAS);
            rayTracingShader.SetAccelerationStructure("g_SceneAccelStruct2", sceneRTAS);
        } else {
            rayTracingShader.SetAccelerationStructure("g_SceneAccelStruct2", sceneRTAS);
            rayTracingShader.SetAccelerationStructure("g_SceneAccelStruct", surfelRTAS);
        }

        rayTracingShader.SetMatrix("g_InvViewMatrix", Camera.main.cameraToWorldMatrix);
        rayTracingShader.SetFloat("g_Zoom", Mathf.Tan(Mathf.Deg2Rad * Camera.main.fieldOfView * 0.5f));
        rayTracingShader.SetFloat("g_Blit", blit ? 1f : 0f);

        rayTracingShader.SetBuffer("g_Surfels", surfels);
        rayTracingShader.SetBuffer("g_Triangles", triangles);

        // output
        rayTracingShader.SetTexture("g_Output", rayTracingOutput);

        rayTracingShader.Dispatch("MainRayGenShader", (int) cameraWidth, (int) cameraHeight, 1);

        if(blit) Graphics.Blit(rayTracingOutput, dest);
        else Graphics.Blit(src, dest);
    }

    public bool blit = false;
    public bool swap = false;

}
