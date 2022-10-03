﻿using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using Unity.Mathematics; // float4x3, float3
using Unity.Collections.LowLevel.Unsafe; // for sizeof(struct)
using System.Threading; // sleep for manual fps limit (reduce heat in summer)
using System.Collections.Generic; // list

public class DXRCamera : MonoBehaviour {

    struct Surfel {
        float4 position;
        float4 rotation;
        float4 color;
        float4 colorDx;
        float4 colorDy;
        float4 data;
    };

    struct AABB {
        public float3 min;
        public float3 max;
    };

    public bool enablePathTracing = false;
    public bool enableLightSampling = false;

    public float surfelDensity = 2f;

    [Range(0.0f, 0.2f)]
    public float sleep = 0f;

    [LogarithmicRangeAttribute(0.001, 1000.0)]
    public float exposure = 2f;

    public bool allowSkySurfels = false;
    public bool showIllumination = false;
    public bool allowStrayRays = false;
    public bool visualizeSurfels = false;

    public bool hasPlacedSurfels = false;
    public ComputeShader surfelDistShader;
    private ComputeBuffer surfels;
    private GraphicsBuffer surfelBounds;
    public RayTracingShader surfelTracingShader;
    public RayTracingShader gptRTShader;

    public int maxNumSurfels = 64 * 1024;

    [HideInInspector]
    public Camera _camera;

    // target texture for raytracing
    [HideInInspector]
    public RenderTexture giTarget;

    // previous GBuffers for motion-vector-improved sample accumulation
    [HideInInspector]
    public Vector3 prevCameraPosition;
    private Vector3 prevCameraOffset;
    private Vector4 prevCameraRotation;

    // summed global illumination
    private RenderTexture emissiveTarget, emissiveDxTarget, emissiveDyTarget;

    // scene structure for raytracing
    [HideInInspector]
    public RayTracingAccelerationStructure sceneRTAS, surfelRTAS;

    // helper material to accumulate raytracing results
    public Material displayMaterial;

    private Matrix4x4 cameraWorldMatrix;

    [HideInInspector]
    public int frameIndex;

    public int skyResolution = 512;

    [HideInInspector]
    public Cubemap skyBox;
    public Camera skyBoxCamera;
    public bool needsSkyBoxUpdate = false;
    
    public bool resetSurfels = true;
    public bool disableSurfaceUpdates = false;
    public Material surfelBoundsMaterial;

    public Mesh cubeMesh;
    public Material surfelMaterial, surfelProcMaterial, surfel2ProcMaterial;
    public bool perPixelRT = false;

    private CommandBuffer cmdBuffer = null;

    private ComputeBuffer countBuffer;

    private ComputeBuffer cubeMeshVertices;

    public bool useProceduralSurfels = false;
    private float lightSampleStrength = 1f, lightAccuArea = 1f;

    private void Start() {

        _camera = GetComponent<Camera>();

        EnableMotionVectors();

        CreateTargets();

        // build scene for raytracing
        InitRaytracingAccelerationStructure();
        sceneRTAS.Build();

        hasPlacedSurfels = false;

        for(int i=0;i<instData.Length;i++){
            instData[i] = Matrix4x4.identity;
        }

    }

    public static int CeilDiv(int a, int d){
        return (a + d - 1) / d;
    }

    private void EnsureSurfels(){
        if(surfels == null || (surfels.count != maxNumSurfels && maxNumSurfels >= 16)) {

            if(surfels != null) surfels.Release();
            surfels = new ComputeBuffer(maxNumSurfels, UnsafeUtility.SizeOf<Surfel>());// 6 * 4 floats is the min size
            hasPlacedSurfels = false;
            
            if(surfelBounds != null) surfelBounds.Release();
            surfelBounds = new GraphicsBuffer(GraphicsBuffer.Target.Structured, maxNumSurfels, UnsafeUtility.SizeOf<AABB>());
            RayTracingAccelerationStructure.RASSettings settings = new RayTracingAccelerationStructure.RASSettings();
            // include all layers
             settings.layerMask = 255;
            // enable automatic updates
            settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Manual;
            // include all renderer types
            settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;
            surfelRTAS = new RayTracingAccelerationStructure(settings);
        }
    }

    private void DistributeSurfels() {

        var shader = surfelDistShader;
        if(shader == null) Debug.Log("Missing surfel shader!");
        EnsureSurfels();

        var depthTex = Shader.GetGlobalTexture("_CameraDepthTexture");
        if(depthTex == null){
            Debug.Log("Missing depth texture");
            return; // is null at the very start of the game
        }

        if(disableSurfaceUpdates && hasPlacedSurfels) return;
        if(resetSurfels) hasPlacedSurfels = false;

        shader.SetFloat("_Time", Time.time);
        shader.SetFloat("_Density", surfelDensity);
        shader.SetFloat("_Far", _camera.farClipPlane);
        shader.SetInt("_FrameIndex", frameIndex);
        shader.SetBool("_AllowSkySurfels", allowSkySurfels);
        
        var transform = _camera.transform;
        shader.SetVector("_CameraPosition", transform.position);
        shader.SetVector("_CameraRotation", QuatToVec(transform.rotation));
        shader.SetVector("_CameraDirection", transform.forward);
        shader.SetVector("_PrevCameraPosition", prevCameraPosition);
        
        float invZFactor = 1f / Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        shader.SetVector("_CameraUVScale", new Vector2(((float)giTarget.height / (giTarget.width)) * invZFactor, invZFactor));

        float zFactor = giTarget.height / (2.0f * Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad));
        shader.SetVector("_CameraOffset", new Vector3((giTarget.width-1) * 0.5f, (giTarget.height-1) * 0.5f, zFactor));

        shader.SetVector("_ZBufferParams", Shader.GetGlobalVector("_ZBufferParams"));

        int kernel;
        if(hasPlacedSurfels) {// update surfels

            kernel = shader.FindKernel("DiscardSmallAndLargeSurfels");
            PrepareDistribution(shader, kernel, depthTex);
            shader.SetBuffer(kernel, "Surfels", surfels);
            Dispatch(shader, kernel, surfels.count, 1, 1);
            
            kernel = shader.FindKernel("SpawnSurfelsInGaps");
            PrepareDistribution(shader, kernel, depthTex);
            shader.SetBuffer(kernel, "Surfels", surfels);
            Dispatch(shader, kernel, CeilDiv(giTarget.width, 16), CeilDiv(giTarget.height, 16), 1);
            
        } else {// init surfels

            kernel = shader.FindKernel("InitSurfelDistribution");
            PrepareDistribution(shader, kernel, depthTex);
            shader.SetBuffer(kernel, "Surfels", surfels);
            Dispatch(shader, kernel, surfels.count, 1, 1);

        }

        hasPlacedSurfels = true;

    }

    public static void Dispatch(ComputeShader shader, int kernel, int x, int y, int z){
        uint gsx, gsy, gsz;
        shader.GetKernelThreadGroupSizes(kernel, out gsx, out gsy, out gsz);
        int sx = CeilDiv(x, (int) gsx);
        int sy = CeilDiv(y, (int) gsy);
        int sz = CeilDiv(z, (int) gsz);
        int maxDim = 1 << 16; // maximum dimensions, why ever...; in OpenGL this is 2B for x, and 65k for y and z on my RTX 3070
        for(x=0;x<sx;x+=maxDim) {
            for(y=0;y<sy;y+=maxDim) {
                for(z=0;z<sz;z+=maxDim) {
                    shader.SetVector("_DispatchOffset", new Vector3(x,y,z));
                    shader.Dispatch(kernel, Mathf.Min(sx-x, maxDim), Mathf.Min(sy-y, maxDim), Mathf.Min(sz-z, maxDim));
                }
            }
        }
    }

    private int PrepareDistribution(ComputeShader shader, int kernel, Texture depthTex){
        
        var t0 = Shader.GetGlobalTexture("_CameraGBufferTexture0");
        var t1 = Shader.GetGlobalTexture("_CameraGBufferTexture1");
        var t2 = Shader.GetGlobalTexture("_CameraGBufferTexture2");
        if(t0 == null || t1 == null || t2 == null){
            Debug.Log("Missing GBuffers");
            return -1;
        }

        shader.SetTexture(kernel, "_CameraGBufferTexture0", t0);
        shader.SetTexture(kernel, "_CameraGBufferTexture1", t1);
        shader.SetTexture(kernel, "_CameraGBufferTexture2", t2);
        shader.SetTexture(kernel, "_CameraDepthTexture", depthTex);

        if(emissiveTarget != null) {
            shader.SetTexture(kernel, "_Weights", emissiveTarget);
        }

        return kernel;
    }

    private void EnableMotionVectors(){
        _camera.depthTextureMode |= DepthTextureMode.Depth | DepthTextureMode.MotionVectors;
    }

	private void CreateTargets() {

        int width = _camera.pixelWidth, height = _camera.pixelHeight;

		giTarget = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Default);
        giTarget.enableRandomWrite = true;
        giTarget.Create();

        emissiveTarget = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Default);
        emissiveTarget.enableRandomWrite = true;
        emissiveTarget.Create();
        emissiveDxTarget = new RenderTexture(emissiveTarget);
        emissiveDyTarget = new RenderTexture(emissiveTarget);
        emissiveDxTarget.Create();
        emissiveDyTarget.Create();

        bool skyBoxMipmaps = false;
        // skybox mipmaps? could be useful for diffuse look at sky, but we currently don't know the ray spread
        // therefore, we couldn't calculate the correct mip level
        skyBox = new Cubemap(skyResolution, TextureFormat.RGBAHalf, skyBoxMipmaps);
        needsSkyBoxUpdate = true;

        GetComponent<PerPixelRT>().CreateTargets(giTarget);

	}

    private void DestroyTargets(){
        giTarget.Release();
        emissiveTarget.Release();
        emissiveDxTarget.Release();
        emissiveDyTarget.Release();
        giTarget = null;
        emissiveTarget = emissiveDxTarget = emissiveDyTarget = null;
        GetComponent<PerPixelRT>().Destroy();
        // skyBox.Release(); // not supported??? 
    }

    private void Update() {
        if(_camera.pixelWidth != giTarget.width || _camera.pixelHeight != giTarget.height){
            DestroyTargets();
            CreateTargets();
            frameIndex = 0;
        }
        if(needsSkyBoxUpdate){
            RenderSky();
            needsSkyBoxUpdate = false;
        }
    }

    private void InitRaytracingAccelerationStructure() {
        RayTracingAccelerationStructure.RASSettings settings = new RayTracingAccelerationStructure.RASSettings();
        // include all layers
        settings.layerMask = ~0;
        // enable automatic updates
        settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Automatic;
        // include all renderer types
        settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;
        var rtas = sceneRTAS = new RayTracingAccelerationStructure(settings);
        // collect all objects in scene and add them to raytracing scene
        Renderer[] renderers = FindObjectsOfType<Renderer>();
        List<Material> materials = new List<Material>();
        foreach (Renderer r in renderers){
            r.GetSharedMaterials(materials);
            int matCount = Mathf.Max(materials.Count, 1);
            RayTracingSubMeshFlags[] subMeshFlags = new RayTracingSubMeshFlags[matCount];
            // Assume all materials are opaque (anyhit shader is disabled) otherwise Material types (opaque, transparent) must be handled here.
            for (int i = 0; i < matCount; i++) // todo mark as transparent if transparent
                subMeshFlags[i] = RayTracingSubMeshFlags.Enabled | RayTracingSubMeshFlags.ClosestHitOnly;
            rtas.AddInstance(r, subMeshFlags);
        }
        // build raytrasing scene
        rtas.Build();
    }

    private void RenderSky(){
        if(skyBoxCamera != null) skyBoxCamera.RenderToCubemap(skyBox, -1);
        else Debug.Log("Missing skybox camera");
    }

    void AccumulateSurfelEmissions() {

        bool useProceduralSurfels = this.useProceduralSurfels;
        if(useDerivatives) {
            useProceduralSurfels = true;
        }

        Material shader = useDerivatives ? surfel2ProcMaterial :
            useProceduralSurfels ? surfelProcMaterial : surfelMaterial;

        EnsureSurfels();

        if(!hasPlacedSurfels){
            Debug.Log("Waiting for surfels to be placed");
            return;
        } else if(shader == null){
            Debug.Log("Missing surfel material");
            return;
        } else if(cubeMesh == null){
            Debug.Log("Missing surfel mesh");
            return;
        }

        if(cmdBuffer == null || cubeMeshVertices == null) {
            Debug.Log("Creating new command buffer");
            cmdBuffer = new CommandBuffer();
            cmdBuffer.name = "Surfel Emission";
            cubeMeshVertices = new ComputeBuffer(3 * 2 * 6, sizeof(float) * 3);
            float3[] vertices = new float3[36];
            Vector3[] srcPositions = cubeMesh.vertices;
            int[] srcTriangles = cubeMesh.triangles;
            // Debug.Log("vertices(24): "+srcPositions.Length+", triangles(36): "+srcTriangles.Length);
            for(int i=0,l=Mathf.Min(srcTriangles.Length,vertices.Length);i<l;i++){
                vertices[i] = srcPositions[srcTriangles[i]];
            }
            cubeMeshVertices.SetData(vertices);
            // _camera.AddCommandBuffer(CameraEvent.AfterGBuffer, cmdBuffer);
        }

        // shader.SetMatrix("_InvViewMatrix", _camera.worldToCameraMatrix.inverse);
        // shader.SetMatrix("_InvProjectionMatrix", _camera.projectionMatrix.inverse);
        float fy = Mathf.Tan(_camera.fieldOfView*Mathf.Deg2Rad*0.5f);
        shader.SetVector("_FieldOfViewFactor", new Vector2(fy*giTarget.width/giTarget.height, fy));
        shader.SetFloat("_AllowSkySurfels", allowSkySurfels ? 1f : 0f);
        shader.SetFloat("_VisualizeSurfels", visualizeSurfels ? 1f : 0f);
        shader.SetFloat("_IdCutoff", 2f / surfelDensity);

        // if(!firstFrame) return; // command buffer doesn't change, only a few shader variables

        cmdBuffer.Clear(); // clear all commands
        if(useDerivatives){
            cmdBuffer.SetRenderTarget(emissiveTarget);
            RenderTargetIdentifier[] targets = {
                emissiveTarget.colorBuffer,
                emissiveDxTarget.colorBuffer,
                emissiveDyTarget.colorBuffer
            };
            cmdBuffer.SetRenderTarget(targets, emissiveTarget.depthBuffer);
        } else {
            cmdBuffer.SetRenderTarget(emissiveTarget);
        }

        // https://docs.unity3d.com/ScriptReference/Rendering.CommandBuffer.SetViewProjectionMatrices.html
        cmdBuffer.SetViewProjectionMatrices(_camera.worldToCameraMatrix, _camera.projectionMatrix);
        var matrix = _camera.projectionMatrix * _camera.worldToCameraMatrix;
        // y is flipped in DirectX with Unity (like described in the docs)
        // since we always use DirectX 12, because it's the only API supporting RayTracing in Unity,
        // we apply this flipping by standard;
        for(int i=1;i<16;i+=4) matrix[i] = -matrix[i];
        shader.SetMatrix("_CustomMVP", matrix);
        Shader.SetGlobalVector("_CameraPos", _camera.transform.position);

        cmdBuffer.ClearRenderTarget(true, true, Color.clear, 1f);// depth, color, color-value, depth-value (default is 1)

        // todo copy original depth into their depth for better performance
        // RenderTexture prev = RenderTexture.active;
        // if(changeRT) Graphics.SetRenderTarget(emissiveTarget);

        shader.SetBuffer("_Surfels", surfels);
        shader.SetBuffer("_Vertices", cubeMeshVertices);
        cmdBuffer.SetGlobalFloat("_SurfelCount", surfels.count);

        int numInstances = surfels.count;
        int pass = -1; // shader.FindPass(""); // which shader pass, or -1 for all
        if(useProceduralSurfels){
            cmdBuffer.SetGlobalFloat("_InstanceIDOffset", 0);
            cmdBuffer.DrawProcedural(Matrix4x4.identity, shader, pass, MeshTopology.Triangles, cubeMeshVertices.count, numInstances);
        } else {
            int offset = 0;
            while(numInstances > 0){
                cmdBuffer.SetGlobalFloat("_InstanceIDOffset", offset);
                cmdBuffer.DrawMeshInstanced(cubeMesh, 0, shader, pass, instData);
                numInstances -= instancesPerBatch;
                offset += instancesPerBatch;
            }
        }
        
        Graphics.ExecuteCommandBuffer(cmdBuffer);
        // cmdBuffer.Release();
        // cmdBuffer = null;

    }

    public bool updateSurfels = false;
    
    private static int instancesPerBatch = 511;// 1023 at max; limitation by Unity :/
    private Matrix4x4[] instData = new Matrix4x4[instancesPerBatch];

    public static Vector4 QuatToVec(Quaternion q){
        return new Vector4(q.x, q.y, q.z, q.w);
    }

    private void PreservePrevTransform(){
        var transform = _camera.transform;
        prevCameraPosition = transform.position;
        prevCameraRotation = QuatToVec(transform.rotation);
    }

    private void SurfelPathTracing(){
        var shader = surfelTracingShader;
        shader.SetAccelerationStructure("_RaytracingAccelerationStructure", sceneRTAS);
        shader.SetInt("_FrameIndex", frameIndex);
        shader.SetVector("_CameraPosition", transform.position);
        shader.SetVector("_CameraRotation", QuatToVec(transform.rotation));
        shader.SetVector("_CameraOffset", CalcCameraOffset());
        shader.SetTexture("_SkyBox", skyBox);
        shader.SetBuffer("_Surfels", surfels);
        shader.SetFloat("_Far", _camera.farClipPlane);
        float tan = Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        shader.SetVector("_CameraUVSize", new Vector2((float) giTarget.width / giTarget.height * tan, tan));
        shader.SetBool("_AllowSkySurfels", allowSkySurfels);
        shader.SetBool("_AllowStrayRays", allowStrayRays);
        shader.SetShaderPass("DxrPass");
        shader.Dispatch("SurfelPathTracing", surfels.count, 1, 1, null);
    }

    public float lightSamplingRatio = 1f;
    public int samplesPerPixel = 1, raysPerSample = 10;

    public Vector3 CalcCameraOffset(){
        float tan = Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        float zFactor = giTarget.height / (2.0f * tan);
        return new Vector3((giTarget.width-1) * 0.5f, (giTarget.height-1) * 0.5f, zFactor);
    }

    public bool useDerivatives = false;
    public int surfelPlacementIterations = 1;

    public bool useOfficalGPT = false;

    [ImageEffectOpaque]
    private void OnRenderImage(RenderTexture source, RenderTexture destination) {

        if(sleep > 0f){
            Thread.Sleep((int) (sleep * 1000));
        }

        var transform = _camera.transform;

        Shader.SetGlobalFloat("_EnableRayDifferentials", useDerivatives ? 1f : 0f);

        // Debug.Log("on-rimage: "+_camera.worldToCameraMatrix);
        if(perPixelRT) {
            var helper = GetComponent<PerPixelRT>();
            helper.RenderImage(this, destination);
        } else {
        
            EnsureSurfels();

            if(updateSurfels) {
                // for faster surfel-coverage, we can use multiple iterations
                bool uds = useDerivatives;
                for(int i=0,l=surfelPlacementIterations;i<l;i++){
                    useDerivatives = false;
                    AccumulateSurfelEmissions();// could be skipped in the first iteration, if really necessary
                    DistributeSurfels();// todo surfels could move along their gradient to more evenly fill the scene
                }
                useDerivatives = uds;
                AccumulateSurfelEmissions();
            } else {
                AccumulateSurfelEmissions();
            }

            if(updateSurfels && surfelTracingShader != null) {
                if(enablePathTracing) SurfelPathTracing();
            }

            var lightSampling = GetComponent<LightSampling>();
            if(lightSampling != null){
                lightSampling.surfels = surfels;
                lightSampling.sceneRTAS = sceneRTAS;
                lightSampling.lightAccuArea = lightAccuArea;
                lightSampling.lightSampleStrength = lightSampleStrength / surfels.count;
                lightSampling.skyBox = skyBox;
                if(enableLightSampling) {
                    lightSampling.RenderImage(_camera);
                }
                if(useOfficalGPT){
                    var shader = gptRTShader;
                   
                    // light sampling is being used via sampleEmitterDirectVisible()
                    lightSampling.enableSky = false;// handled separately in GPT
                    lightSampling.CollectEmissiveTriangles(_camera); // to do can be cached, if the scene is static
                    shader.SetAccelerationStructure("_RaytracingAccelerationStructure", sceneRTAS);
                    shader.SetFloat("_LightAccuArea", lightSampling.lightAccuArea);
                    shader.SetBuffer("g_Triangles", lightSampling.emissiveTriangles);

                    shader.SetVector("_CameraPosition", transform.position);
                    shader.SetVector("_CameraRotation", QuatToVec(transform.rotation));
                    float tan = Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
                    shader.SetVector("_CameraUVSize", new Vector2((float) giTarget.width / giTarget.height * tan, tan));
                    shader.SetFloat("_Far", _camera.farClipPlane);
                    shader.SetInt("_FrameIndex", frameIndex);
                    shader.SetTexture("_SkyBox", skyBox);
                    shader.SetBuffer("_Surfels", surfels);
                    shader.Dispatch("SurfelGPT", giTarget.width, giTarget.height, 1, _camera);
                }
            }

            var poissonReconstr = GetComponent<PoissonReconstruction>();
            var accu = emissiveTarget;
            if(useDerivatives && poissonReconstr != null && poissonReconstr.enabled){
                accu = poissonReconstr.poissonReconstruct( emissiveTarget, emissiveDxTarget, emissiveDyTarget );
            }

            // display result on screen
            displayMaterial.SetVector("_Duv", new Vector2(1f/(_camera.pixelWidth-1f), 1f/(_camera.pixelHeight-1f)));
            displayMaterial.SetFloat("_DivideByAlpha", 1f);
            displayMaterial.SetTexture("_SkyBox", skyBox);
            displayMaterial.SetFloat("_Exposure", exposure);
            displayMaterial.SetTexture("_Accumulation", accu);
            displayMaterial.SetTexture("_AccuDx", emissiveDxTarget);
            displayMaterial.SetTexture("_AccuDy", emissiveDyTarget);
            displayMaterial.SetFloat("_Derivatives", useDerivatives ? 1f : 0f);
            displayMaterial.SetFloat("_Far", _camera.farClipPlane);
            displayMaterial.SetFloat("_ShowIllumination", showIllumination ? 1f : 0f);
            displayMaterial.SetFloat("_VisualizeSurfels", visualizeSurfels ? 1f : 0f);
            displayMaterial.SetVector("_CameraPosition", _camera.transform.position);
            displayMaterial.SetVector("_CameraRotation", QuatToVec(transform.rotation));
            float zFactor = 1.0f / Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
            displayMaterial.SetVector("_CameraScale", new Vector2((zFactor * _camera.pixelWidth) / _camera.pixelHeight, zFactor));
            Graphics.Blit(null, destination, displayMaterial);
            
        }

        PreservePrevTransform();

        frameIndex++;

    }

    private void OnDestroy() {
        DestroyTargets();
        if(sceneRTAS != null) sceneRTAS.Release();
        if(surfelRTAS != null) surfelRTAS.Release();
        if(countBuffer != null) countBuffer.Release();
        countBuffer = null;
        if(cubeMeshVertices != null) cubeMeshVertices.Release();
        cubeMeshVertices = null;
        if(_camera != null && cmdBuffer != null) {
            _camera.RemoveCommandBuffer(CameraEvent.AfterGBuffer, cmdBuffer);
        }
        if(cmdBuffer != null){
            cmdBuffer.Release();
            cmdBuffer = null;
        }
        if(surfels != null){ 
            surfels.Release();
            surfels = null;
        }
        if(surfelBounds != null){
            surfelBounds.Release();
            surfelBounds = null;
        }
    }

}