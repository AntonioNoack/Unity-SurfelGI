using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using Unity.Mathematics; // float4x3, float3
using Unity.Collections.LowLevel.Unsafe; // for sizeof(struct)
using System; // invalid operation exception
using System.Collections.Generic; // list

/**
 * This class implements SurfelGI.
 */
public class SurfelGI : MonoBehaviour {

    struct AABB {
        public float3 min;
        public float3 max;
    };

    public enum Substrate {
        PIXEL,
        SURFEL,
    };

    public enum Result {
        SURFEL_WEIGHTS,
        GLOBAL_ILLUMINATION,
        COLOR,
    };

    public Substrate substrate = Substrate.PIXEL;
    public Result result = Result.COLOR;

    /**
     * When using per-pixel path-tracing, the GI can be blurred with this radius to give less noisy results.
     */
    public int pixelGIBlur = 5;
    public float surfelDensity = 2f;

    [LogarithmicRangeAttribute(0.001, 1000.0)]
    public float exposure = 2f;

    public bool hasPlacedSurfels = false;

    // use fibonacci sphere as initial distribution; false = use hilbert mapping
    // advantage: easy, disadvantage: horrible cache locality except at poles
    public bool useFibSphere = false; 

    // respawns surfels roughly where they were originally; probably causes temporal instability issues, if too many surfels are required locally
    // advantage: should increase cache locality
    public bool respawnSurfelsAtOrigin = false;
    public bool visualizeSurfelIds = false;

    public ComputeShader surfelDistShader;
    private ComputeBuffer surfels;
    private GraphicsBuffer surfelBounds;
    public RayTracingShader surfelTracingShader;

    public int maxNumSurfels = 64 * 1024;
    public float minSurfelWeight = 0.05f;
    public bool enableSurfelMovement = false;

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
    [HideInInspector]
    public RenderTexture emissiveTarget;

    // scene structure for raytracing
    [HideInInspector]
    public RayTracingAccelerationStructure sceneRTAS, surfelRTAS;

    // helper material to accumulate raytracing results
    public Material displayMaterial;

    [HideInInspector]
    public int frameIndex;

    [HideInInspector]
    public Cubemap skyBox;
    public Camera skyBoxCamera;
    public int skyResolution = 512;
    public bool needsSkyBoxUpdate = false;
    
    public bool resetSurfels = true;
    public bool resetPixelGI = true;
    public bool resetEmissiveTriangles = true;

    public bool disableSurfaceUpdates = false;

    public Mesh cubeMesh;
    public Material surfelProcMaterial;

    private CommandBuffer cmdBuffer;
    private ComputeBuffer countBuffer, cubeMeshVertices;

    private void Start() {

        // we are limited to 120 fps, even if nothing is running, and VSync is disabled... why?
        // UnityEngine.Application.targetFramerate = 5000;

        OnDestroy();

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
            surfels = new ComputeBuffer(maxNumSurfels, 6 * 4 * 4);// 6 * 4 floats is the min size
            surfels.name = "Surfels";
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
        if(resetSurfels) {
            hasPlacedSurfels = false;
            // resetSurfels = false;
        }

        shader.SetFloat("_Time", Time.time);
        shader.SetFloat("_Density", surfelDensity);
        shader.SetFloat("_Far", _camera.farClipPlane);
        shader.SetInt("_FrameIndex", frameIndex);
        
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
        shader.SetFloat("_EnableSurfelMovement", enableSurfelMovement ? 1f : 0f);
        shader.SetFloat("_MinimumSurfelWeight", minSurfelWeight);
        shader.SetFloat("_UseFibSphere", useFibSphere ? 1f : 0f);
        shader.SetFloat("_RespawnAtOrigin", respawnSurfelsAtOrigin ? 1f : 0f);

        int kernel;
        if(hasPlacedSurfels) {// update surfels

            kernel = shader.FindKernel("DiscardSmallAndLargeSurfels");
            if(kernel < 0) error("Kernel DiscardSmallAndLargeSurfels is missing");
            PrepareDistribution(shader, kernel);
            shader.SetBuffer(kernel, "Surfels", surfels);
            Dispatch(shader, kernel, surfels.count, 1, 1);
            
            kernel = shader.FindKernel("SpawnSurfelsInGaps");
            if(kernel < 0) error("Kernel SpawnSurfelsInGaps is missing");
            PrepareDistribution(shader, kernel);
            shader.SetBuffer(kernel, "Surfels", surfels);
            Dispatch(shader, kernel, CeilDiv(giTarget.width, 16), CeilDiv(giTarget.height, 16), 1);
            
        } else {// init surfels

            kernel = shader.FindKernel("InitSurfelDistribution");
            if(kernel < 0) error("Kernel InitSurfelDistribution is missing");
            PrepareDistribution(shader, kernel);
            shader.SetBuffer(kernel, "Surfels", surfels);
            Dispatch(shader, kernel, surfels.count, 1, 1);

        }

        if(!hasPlacedSurfels) frameIndex = 0;
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

    private int PrepareDistribution(ComputeShader shader, int kernel){
        
        var t0 = Shader.GetGlobalTexture("_CameraGBufferTexture0");
        var t1 = Shader.GetGlobalTexture("_CameraGBufferTexture1");
        var t2 = Shader.GetGlobalTexture("_CameraGBufferTexture2");
        var t3 = Shader.GetGlobalTexture("_CameraDepthTexture");
        if(t0 == null || t1 == null || t2 == null || t3 == null){
            Debug.Log("Missing GBuffers");
            return -1;
        }

        if(t0.width != t1.width || t0.width != t2.width || t0.width != t3.width) error("Widths are inconsistent");
        if(t0.height != t1.height || t0.height != t2.height || t0.height != t3.height) error("Heights are inconsistent");

        shader.SetTexture(kernel, "_CameraGBufferTexture0", t0);
        shader.SetTexture(kernel, "_CameraGBufferTexture1", t1);
        shader.SetTexture(kernel, "_CameraGBufferTexture2", t2);
        shader.SetTexture(kernel, "_CameraDepthTexture", t3);

        if(emissiveTarget != null) {
            shader.SetTexture(kernel, "_Weights", emissiveTarget);
        }

        return kernel;
    }

    private static void error(string message){
        // C# is stupid... why is there no such thing?
        // throw new InvalidStateException(message);
        throw new InvalidOperationException(message);
    }

    private void EnableMotionVectors(){
        _camera.depthTextureMode |= DepthTextureMode.Depth | DepthTextureMode.MotionVectors;
    }

	private void CreateTargets() {

        int width = _camera.pixelWidth, height = _camera.pixelHeight;

		giTarget = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Default);
        giTarget.enableRandomWrite = true;
        giTarget.Create();

        emissiveTarget = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Default);
        emissiveTarget.enableRandomWrite = true;
        emissiveTarget.Create();

        bool skyBoxMipmaps = false;
        // skybox mipmaps? could be useful for diffuse look at sky, but we currently don't know the ray spread
        // therefore, we couldn't calculate the correct mip level
        skyBox = new Cubemap(skyResolution, TextureFormat.RGBAFloat, skyBoxMipmaps);
        needsSkyBoxUpdate = true;

        GetComponent<PerPixelRT>().CreateTargets(giTarget);

	}

    private void DestroyTargets(){
        if(giTarget != null) giTarget.Release();
        if(emissiveTarget != null) emissiveTarget.Release();
        giTarget = null;
        emissiveTarget = null;
        GetComponent<PerPixelRT>()?.Destroy();
        // skyBox.Release(); // not supported??? 
    }

    private void Update() {
        if(_camera == null){
            Debug.Log("Camera is missing");
            return;
        }
        if(_camera.pixelWidth != giTarget.width || _camera.pixelHeight != giTarget.height) {
            Debug.Log("Resizing");
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
            for (int i = 0; i < matCount; i++){ // mark as transparent if transparent
                if(materials[i].HasProperty("_IsTrMarker"))
                    subMeshFlags[i] = RayTracingSubMeshFlags.Enabled;
                else // closest hit only = any-hit shader is ignored; setting this might be unnecessary, but maybe it's faster
                    subMeshFlags[i] = RayTracingSubMeshFlags.Enabled | RayTracingSubMeshFlags.ClosestHitOnly;
            }
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

        Material shader = surfelProcMaterial;

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
            cubeMeshVertices.name = "Cube Mesh Vertices";
            float3[] vertices = new float3[36];
            Vector3[] srcPositions = cubeMesh.vertices;
            int[] srcTriangles = cubeMesh.triangles;
            for(int i=0,l=Mathf.Min(srcTriangles.Length,vertices.Length);i<l;i++){
                vertices[i] = srcPositions[srcTriangles[i]];
            }
            cubeMeshVertices.SetData(vertices);
        }

        float fy = Mathf.Tan(_camera.fieldOfView*Mathf.Deg2Rad*0.5f);
        shader.SetVector("_FieldOfViewFactor", new Vector2(fy*giTarget.width/giTarget.height, fy));
        shader.SetFloat("_VisualizeSurfels", result == Result.SURFEL_WEIGHTS ? 1f : 0f);
        shader.SetFloat("_IdCutoff", 2f / surfelDensity);
        shader.SetFloat("_VisualizeSurfelIds", visualizeSurfelIds && result == Result.SURFEL_WEIGHTS ? 1f : 0f);
        shader.SetVector("_Duv", new Vector2(1f/giTarget.width, 1f/giTarget.height));

        cmdBuffer.Clear(); // clear all commands
        cmdBuffer.SetRenderTarget(emissiveTarget);

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

        shader.SetBuffer("_Surfels", surfels);
        shader.SetBuffer("_Vertices", cubeMeshVertices);
        cmdBuffer.SetGlobalFloat("_SurfelCount", surfels.count);

        int numInstances = surfels.count;
        int pass = -1; // which shader pass, or -1 for all
        
        cmdBuffer.SetGlobalFloat("_InstanceIDOffset", 0);
        cmdBuffer.DrawProcedural(Matrix4x4.identity, shader, pass, MeshTopology.Triangles, cubeMeshVertices.count, numInstances);
        
        Graphics.ExecuteCommandBuffer(cmdBuffer);

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
        InitPathTracing(true).Dispatch("SurfelPathTracing", surfels.count, 1, 1, null);
    }
    
    public RayTracingShader InitPathTracing(bool needsSurfels){
        var shader = surfelTracingShader;
        shader.SetAccelerationStructure("_RaytracingAccelerationStructure", sceneRTAS);
        shader.SetInt("_FrameIndex", frameIndex);
        shader.SetVector("_CameraPosition", transform.position);
        shader.SetVector("_CameraRotation", QuatToVec(transform.rotation));
        shader.SetVector("_CameraOffset", CalcCameraOffset());
        shader.SetTexture("_SkyBox", skyBox);
        if(needsSurfels) shader.SetBuffer("_Surfels", surfels);
        shader.SetInt("_SPP", samplesPerPixel);
        shader.SetInt("_RPS", raysPerSample);
        shader.SetFloat("_Near", _camera.nearClipPlane);
        shader.SetFloat("_Far", _camera.farClipPlane);
        float tan = Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        shader.SetVector("_CameraUVSize", new Vector2((float) giTarget.width / giTarget.height * tan, tan));
        shader.SetShaderPass("DxrPass");
        return shader;
    }

    public int samplesPerPixel = 1, raysPerSample = 10;

    public Vector3 CalcCameraOffset(){
        float tan = Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        float zFactor = giTarget.height / (2.0f * tan);
        return new Vector3((giTarget.width-1) * 0.5f, (giTarget.height-1) * 0.5f, zFactor);
    }

    public int surfelPlacementIterations = 1;

    [ImageEffectOpaque]
    private void OnRenderImage(RenderTexture source, RenderTexture destination) {

        if(doNothingCtr > 0){
            doNothingCtr--;
            return;// safety first (a try to prevent crashes)
        }

        if(_camera == null){
            Debug.Log("Camera is null");
            return;
        }

        if(sceneRTAS == null)
            InitRaytracingAccelerationStructure();

        var usePixelPT1 = GetComponent<PerPixelRT>();
        
        if(result == Result.SURFEL_WEIGHTS || substrate == Substrate.SURFEL){
            EnsureSurfels();
            if(updateSurfels) {
                // for faster surfel-coverage, we can use multiple iterations
                for(int i=0,l=surfelPlacementIterations;i<l;i++){
                    AccumulateSurfelEmissions();// could be skipped in the first iteration, if really necessary
                    DistributeSurfels();
                }
                AccumulateSurfelEmissions();
            } else {
                AccumulateSurfelEmissions();
            }

            if(updateSurfels && surfelTracingShader != null && substrate == Substrate.SURFEL) {
                SurfelPathTracing();
            }
        }

        var transform = _camera.transform;
        if(substrate == Substrate.PIXEL && result != Result.SURFEL_WEIGHTS){
            usePixelPT1.UpdatePixelGI(this);
        }

        var accu = emissiveTarget;
        if(result != Result.SURFEL_WEIGHTS && substrate == Substrate.PIXEL){
            accu = usePixelPT1.AccumulatePixelGI(this, accu);
        }

        // display result on screen
        displayMaterial.SetVector("_Duv", new Vector2(1f/(_camera.pixelWidth-1f), 1f/(_camera.pixelHeight-1f)));
        displayMaterial.SetFloat("_DivideByAlpha", 1f);
        displayMaterial.SetInt("_PixelGIBlur", pixelGIBlur);
        displayMaterial.SetTexture("_SkyBox", skyBox);
        displayMaterial.SetFloat("_Exposure", exposure);
        displayMaterial.SetTexture("_Accumulation", accu);
        displayMaterial.SetFloat("_Derivatives", 0f);
        displayMaterial.SetFloat("_Far", _camera.farClipPlane);
        displayMaterial.SetFloat("_ShowIllumination", result == Result.GLOBAL_ILLUMINATION ? 1f : 0f);
        displayMaterial.SetFloat("_VisualizeSurfels", result == Result.SURFEL_WEIGHTS ? 1f : 0f);
        displayMaterial.SetVector("_CameraPosition", _camera.transform.position);
        displayMaterial.SetVector("_CameraRotation", QuatToVec(transform.rotation));
        float zFactor = 1.0f / Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        displayMaterial.SetVector("_CameraScale", new Vector2((zFactor * _camera.pixelWidth) / _camera.pixelHeight, zFactor));
        Graphics.Blit(null, destination, displayMaterial);

        if(result != Result.SURFEL_WEIGHTS && substrate == Substrate.PIXEL){
            usePixelPT1.PreservePrevGBuffers();
            usePixelPT1.SwapAccumulationTextures();
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