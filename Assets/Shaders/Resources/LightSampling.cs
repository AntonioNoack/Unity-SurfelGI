using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Experimental.Rendering;
using Unity.Collections.LowLevel.Unsafe; // for sizeof(struct)
using Unity.Mathematics; // float4x3, float3
using System.Collections.Generic;

public class LightSampling : MonoBehaviour {

    public ComputeShader aabbShader;
    public ComputeShader surfelToAABBShader;

    public ComputeBuffer surfels;

    public RayTracingShader rayTracingShader1, rayTracingShader2;
    public ComputeShader testPass3Shader;

    public Material proceduralMaterial;

    public RayTracingAccelerationStructure surfelRTAS, sceneRTAS;

    public float lightSampleStrength = 1f;
    public float lightAccuArea = 1f;

    private MaterialPropertyBlock properties;
    private GraphicsBuffer aabbList;
    private ComputeBuffer samples;

    public struct AABB {
        public float3 min;
        public float3 max;
    };

    struct EmissiveTriangle {
        public float ax,ay,az,bx,by,bz,cx,cy,cz;
        public float r,g,b;
        public float accuIndex, pad0, pad1, pad2;
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

        if(emissiveTriangles != null){
            emissiveTriangles.Release();
            emissiveTriangles = null;
        }

    }

    private int frameIndex = 0;
    
    public Mesh skyMesh;

    public Shader emissiveDXRShader;
    private ComputeBuffer emissiveTriangles;

    public Vector3 sunDir;
    public Vector2 skySunRatio;// todo calculate or guess how emissive the sun is, and how emissive the sky is overall
    public float invSunSize = 20f;

    public bool normalizeWeights = false;

    private float SkySampleDensity(Vector3 v){
        // must be identical to SkyToTris.compute
        float skyDensity = 1f;// mostly contant, probably slightly less at the bottom
        float x = Vector3.Dot(sunDir, v)/v.magnitude;

        // this is an integral over a linear section, which is technically incorrect;
        // however, this is a guess, and a sampling density only, so
        // it doesn't have that much of an effect

        // correct form: integrate (angleToSunCenter < sunRadiusOnSky ? 1 : 0) * acos(x)
        // assuming the sun is a constant-colored disk

        float sunIntegral = 0.5f * invSunSize;
        float sunDensity = Mathf.Max(1f - (1f-x) / invSunSize, 0f) / sunIntegral;// sharp around the sun, depending on _ClearSky

        // return "good" density: monotone for cloudy sky (except for floor maybe), strong for sunny, clear sky
        // total sum doesn't matter too much, as long as we know it, and adjust for it as a sky vs scene light brightness
        return Vector2.Dot(skySunRatio, new float2(skyDensity, sunDensity));
    }

    private Vector3[] GetVertices(Mesh mesh, Matrix4x4 transform){
        Vector3[] vertices = mesh.vertices;
        // convert vertices from local space to global space
        if(transform != null) for(int i=0;i<vertices.Length;i++){
            vertices[i] = transform.MultiplyPoint3x4(vertices[i]);
        }
        return vertices;
    }

    private void AddMesh1(Mesh mesh, Vector3[] vertices, float brightness, ref float totalEmission, ref int numTris){
        float meshArea = 0f;
        int[] triangles = mesh.triangles;
        for(int i=0;i<triangles.Length;){
            Vector3 a = vertices[triangles[i++]], b = vertices[triangles[i++]], c = vertices[triangles[i++]];
            meshArea += Vector3.Cross(b-a,c-a).magnitude;
        }
        totalEmission += meshArea * brightness;
        numTris += triangles.Length;
    }

    private void AddMesh2(Mesh mesh, Vector3[] vertices, Vector3 color, float brightness, EmissiveTriangle[] tris, ref int numTris, ref float accuArea){
        int[] triangles = mesh.triangles;
        for(int i=0;i<triangles.Length;){
            Vector3 a = vertices[triangles[i++]], b = vertices[triangles[i++]], c = vertices[triangles[i++]];
            float area = Vector3.Cross(b-a,c-a).magnitude;
            EmissiveTriangle tri;
            tri.ax = a.x;tri.ay = a.y;tri.az = a.z;
            tri.bx = b.x;tri.by = b.y;tri.bz = b.z;
            tri.cx = c.x;tri.cy = c.y;tri.cz = c.z;
            float samplingDensity = brightness;// todo also base on distance to camera
            var color2 = color / samplingDensity;
            tri.r = color2.x;tri.g = color2.y;tri.b = color2.z;
            accuArea += area * samplingDensity;
            tri.accuIndex = accuArea;
            tri.pad0 = tri.pad1 = tri.pad2 = 0;
            tris[numTris++] = tri;
        }
    }

    private void AddSunMesh2(Mesh mesh, Vector3[] vertices, Vector3 color, float brightness, EmissiveTriangle[] tris, ref int numTris, ref float accuArea){
        int[] triangles = mesh.triangles;
        for(int i=0;i<triangles.Length;){
            Vector3 a = vertices[triangles[i++]], b = vertices[triangles[i++]], c = vertices[triangles[i++]];
            float area = Vector3.Cross(b-a,c-a).magnitude;
            EmissiveTriangle tri;
            tri.ax = a.x;tri.ay = a.y;tri.az = a.z;
            tri.bx = b.x;tri.by = b.y;tri.bz = b.z;
            tri.cx = c.x;tri.cy = c.y;tri.cz = c.z;
            float samplingDensity = SkySampleDensity(new Vector3(a.x+b.x+c.x, a.y+b.y+c.y, a.z+b.z+c.z));
            var color2 = color / samplingDensity;
            tri.r = color2.x;tri.g = color2.y;tri.b = color2.z;
            accuArea += area * samplingDensity;
            tri.accuIndex = accuArea;
            tri.pad0 = tri.pad1 = tri.pad2 = 0;
            tris[numTris++] = tri;
        }
    }

    private void CollectEmissiveTriangles(Camera camera){

        MeshRenderer[] renderers = FindObjectsOfType<MeshRenderer>();

        if(skyMesh == null){
            Debug.LogWarning("Missing sky mesh");
            return;
        } else if(emissiveDXRShader == null){
            Debug.LogWarning("Missing Emissive DXR Shader for finding emissive triangles");
            return;
        }

        int numTris = 0;
        float totalEmission = 0f;

        // move sky mesh
        // guessed sky color; only amplitude matters here
        Vector3 skyColor = new Vector3(1f,1f,1f);
        float skySize = 1000f;
        Matrix4x4 skyTransform = Matrix4x4.Translate(camera.transform.position) * Matrix4x4.Scale(new Vector3(skySize,skySize,skySize));
        float skyBrightness = (skyColor.x + skyColor.y + skyColor.z) / 3f;
        Vector3[] skyVertices = GetVertices(skyMesh, skyTransform);
        AddMesh1(skyMesh, skyVertices, skyBrightness, ref totalEmission, ref numTris);

        // for updating the sky
        int numSkyTris = numTris;

        foreach (MeshRenderer r in renderers) {
            var mat = r.sharedMaterial;
            bool isEmissive = mat != null && mat.shader == emissiveDXRShader;
            if(isEmissive) {
                MeshFilter filter = r.GetComponent<MeshFilter>();
                Color color = mat.GetColor("_Color");
                float brightness = (color.r + color.g + color.b) / 3f;
                if(filter != null && brightness > 0){
                    // calculate surface area and count triangles
                    Mesh mesh = filter.sharedMesh;
                    AddMesh1(mesh, GetVertices(mesh, r.transform.localToWorldMatrix),
                        brightness, ref totalEmission, ref numTris);
                }
            }
        }
        numTris /= 3;

        EmissiveTriangle[] tris = new EmissiveTriangle[numTris];
        numTris = 0;
        float accuArea = 0f;

        // use sampling distribution for triangle importance guesses
        AddSunMesh2(skyMesh, skyVertices, skyColor, skyBrightness, tris, ref numTris, ref accuArea);

        // todo execute sky-update shader

        foreach (MeshRenderer r in renderers) {
            var mat = r.sharedMaterial;
            bool isEmissive = mat != null && mat.shader == emissiveDXRShader;
            if(isEmissive) {
                MeshFilter filter = r.GetComponent<MeshFilter>();
                Color color = mat.GetColor("_Color");
                float brightness = (color.r + color.g + color.b) / 3f;
                Vector3 color3 = new Vector3(color.r, color.g, color.b);
                if(filter != null && brightness > 0){
                    // calculate surface area and count triangles
                    Mesh mesh = filter.sharedMesh;
                    AddMesh2(mesh, GetVertices(mesh, r.transform.localToWorldMatrix),
                        color3, brightness, tris, ref numTris, ref accuArea);
                }
            }
        }

        lightAccuArea = accuArea;
        lightSampleStrength = totalEmission * 0.5f;

        // save all triangles to compute buffer
        emissiveTriangles = new ComputeBuffer(tris.Length, 2 * UnsafeUtility.SizeOf<EmissiveTriangle>());
        Debug.Log("sizeof(EmissiveTriangle) = "+UnsafeUtility.SizeOf<EmissiveTriangle>());
        emissiveTriangles.SetData(tris);

        totalEmission *= 0.5f; // calculate the actual area for correct debugging

        Debug.Log("Collected "+tris.Length+" triangles with a total emission of "+totalEmission);

    }

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

    public void RenderImage(Camera camera) {

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

        // todo we also need to update them, if the sky density changes drastically, e.g. when the sun is moving
        if(emissiveTriangles == null) {
            CollectEmissiveTriangles(camera);
        }

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
            surfels == null || samples == null || emissiveTriangles == null || 
            surfelRTAS == null || sceneRTAS == null ||
            rayTracingShader1 == null || rayTracingShader2 == null || testPass3Shader == null
        ) {
            Debug.LogWarning("Some property is null!");
            return;
        }

        {
            var shader = rayTracingShader1;
            shader.SetShaderPass("Test");
            shader.SetAccelerationStructure("_RaytracingAccelerationStructure", sceneRTAS);
            shader.SetBuffer("g_Surfels", surfels);
            shader.SetBuffer("g_Samples", samples);
            shader.SetBuffer("g_Triangles", emissiveTriangles);
            shader.SetInt("_FrameIndex", frameIndex);
            shader.SetFloat("_LightAccuArea", lightAccuArea);
            shader.Dispatch("TestPass1", surfels.count, 1, 1);

            shader = rayTracingShader2;
            shader.SetShaderPass("Test");
            shader.SetAccelerationStructure("_RaytracingAccelerationStructure", surfelRTAS);
            shader.SetBuffer("g_Surfels", surfels);
            shader.SetBuffer("g_Samples", samples);
            shader.SetBuffer("g_Triangles", emissiveTriangles);
            shader.SetInt("_FrameIndex", frameIndex);
            shader.SetFloat("_Strength", lightSampleStrength);
            shader.Dispatch("TestPass2", surfels.count, 1, 1);
        }

        if(normalizeWeights){
            var shader = testPass3Shader;
            int kernel = shader.FindKernel("AddLightSampleWeights");
            shader.SetBuffer(kernel, "g_Surfels", surfels);
            shader.SetFloat("_DeltaWeight", 1f);
            DXRCamera.Dispatch(shader, kernel, surfels.count, 1, 1);
        }

    }

}
