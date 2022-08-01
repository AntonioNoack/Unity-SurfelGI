using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using Unity.Mathematics; // float4x3, float3
using Unity.Collections.LowLevel.Unsafe; // for sizeof(struct)
using System.Threading; // sleep for manual fps limit (reduce heat in summer)

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
        float3 min;
        float3 max;
    };

    struct EmissiveTriangle {
        public float3 posA, posB, posC;
        public float3 color;
    };

    public float surfelDensity = 2f;

    [Range(0.0f, 0.2f)]
    public float sleep = 0f;

    public bool allowSkySurfels = false;
    public bool showIllumination = false;
    public bool allowStrayRays = false;
    public bool visualizeSurfels = false;

    public bool hasPlacedSurfels = false;
    public ComputeShader surfelDistShader;
    private ComputeBuffer surfels, surfelBounds;
    public RayTracingShader surfelTracingShader;

    public int maxNumSurfels = 64 * 1024;

    private Camera _camera;
    // target texture for raytracing
    private RenderTexture giTarget;
    // textures for accumulation
    private RenderTexture accu1;
    private RenderTexture accu2;

    // previous GBuffers for motion-vector-improved sample accumulation
    private Vector3 prevCameraPosition;
    private Vector3 prevCameraOffset;
    private Vector4 prevCameraRotation;
    private RenderTexture prevGBuff0, prevGBuff1, prevGBuff2, prevGBuffD;

    // summed global illumination
    private RenderTexture emissiveTarget, emissiveDxTarget, emissiveDyTarget, emissiveIdTarget;

    // scene structure for raytracing
    private RayTracingAccelerationStructure sceneRTAS, surfelRTAS;

    // raytracing shader
    public RayTracingShader rayTracingShader;
    // helper material to accumulate raytracing results
    public Material accuMaterial, displayMaterial;
    public Material copyGBuffMat0, copyGBuffMat1, copyGBuffMat2, copyGBuffMatD;

    private Matrix4x4 cameraWorldMatrix;

    private int frameIndex;

    public int skyResolution = 512;
    private Cubemap skyBox;
    public Camera skyBoxCamera;
    public bool needsSkyBoxUpdate = false;

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

    private int CeilDiv(int a, int d){
        return (a + d - 1) / d;
    }
    
    public bool resetSurfels = true;
    public bool disableSurfaceUpdates = false;
    public Material surfelBoundsMaterial;

    private void DistributeSurfels() {

        var shader = surfelDistShader;
        if(shader == null) Debug.Log("Missing surfel shader!");
        if(surfels == null || (surfels.count != maxNumSurfels && maxNumSurfels >= 16)) {
            if(surfels != null) surfels.Release();
            surfels = new ComputeBuffer(maxNumSurfels, UnsafeUtility.SizeOf<Surfel>());
            surfelBounds = new ComputeBuffer(maxNumSurfels, 4 * 3 * 2);// size of AABB
            hasPlacedSurfels = false;
            RayTracingAccelerationStructure.RASSettings settings = new RayTracingAccelerationStructure.RASSettings();
            // include all layers
            settings.layerMask = ~0;
            // enable automatic updates
            // todo does this work with updates to the surfels?
            settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Automatic;
            // include all renderer types
            settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;
            surfelRTAS = new RayTracingAccelerationStructure(settings);
            var properties = new MaterialPropertyBlock();
            properties.SetBuffer("AABBs", surfelBounds);
            properties.SetBuffer("Surfels", surfels);
            surfelRTAS.AddInstance(surfelBounds, maxNumSurfels, false, Matrix4x4.identity, surfelBoundsMaterial, true, properties);
            surfelRTAS.Build();
        }

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

    private void Dispatch(ComputeShader shader, int kernel, int x, int y, int z){
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

        accu1 = new RenderTexture(giTarget);
        accu2 = new RenderTexture(giTarget);

        prevGBuff0 = new RenderTexture(width, height, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Default);
        prevGBuff0.enableRandomWrite = true;
        prevGBuff1 = new RenderTexture(prevGBuff0);
        prevGBuff2 = new RenderTexture(prevGBuff0);
        prevGBuffD = new RenderTexture(width, height, 0, RenderTextureFormat.RFloat, RenderTextureReadWrite.Default);

        emissiveTarget = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Default);
        emissiveTarget.enableRandomWrite = true;
        emissiveTarget.Create();
        emissiveDxTarget = new RenderTexture(emissiveTarget);
        emissiveDyTarget = new RenderTexture(emissiveTarget);
        emissiveDxTarget.Create();
        emissiveDyTarget.Create();
        emissiveIdTarget = new RenderTexture(width, height, 0, RenderTextureFormat.RInt, RenderTextureReadWrite.Default);
        emissiveIdTarget.enableRandomWrite = true;
        emissiveIdTarget.Create();

        prevGBuff1.enableRandomWrite = true;
        prevGBuff2.enableRandomWrite = true;
        prevGBuffD.enableRandomWrite = true;

        prevGBuff0.Create();
        prevGBuff1.Create();
        prevGBuff2.Create();
        prevGBuffD.Create();

        bool skyBoxMipmaps = false;
        // skybox mipmaps? could be useful for diffuse look at sky, but we currently don't know the ray spread
        // therefore, we couldn't calculate the correct mip level
        skyBox = new Cubemap(skyResolution, TextureFormat.RGBAHalf, skyBoxMipmaps);
        needsSkyBoxUpdate = true;

	}

    private void DestroyTargets(){
        giTarget.Release();
        accu1.Release();
        accu2.Release();
        prevGBuff0.Release();
        prevGBuff1.Release();
        prevGBuff2.Release();
        prevGBuffD.Release();
        emissiveTarget.Release();
        emissiveDxTarget.Release();
        emissiveDyTarget.Release();
        emissiveIdTarget.Release();
        giTarget = accu1 = accu2 = null;
        prevGBuff0 = prevGBuff1 = prevGBuff2 = prevGBuffD = null;
        emissiveTarget = emissiveDxTarget = emissiveDyTarget = emissiveIdTarget = null;
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
        foreach (Renderer r in renderers){
            rtas.AddInstance(r);
        }
        // build raytrasing scene
        rtas.Build();
    }

    private void RenderSky(){
        if(skyBoxCamera != null) skyBoxCamera.RenderToCubemap(skyBox, -1);
        else Debug.Log("Missing skybox camera");
    }

    public Mesh cubeMesh;
    public Material surfelMaterial, surfelProcMaterial, surfel2ProcMaterial;
    public bool doRT = false;

    private CommandBuffer cmdBuffer = null;

    private ComputeBuffer countBuffer;

    private ComputeBuffer cubeMeshVertices;

    public bool useProceduralSurfels = false;

    void AccumulateSurfelEmissions() {

        bool useProceduralSurfels = this.useProceduralSurfels;
        if(useDerivatives) {
            useProceduralSurfels = true;
        }

        Material shader = useDerivatives ? surfel2ProcMaterial :
            useProceduralSurfels ? surfelProcMaterial : surfelMaterial;

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

        if(cmdBuffer == null) {
            Debug.Log("Creating new command buffer");
            cmdBuffer = new CommandBuffer();
            cmdBuffer.name = "Surfel Emission";
            cubeMeshVertices = new ComputeBuffer(3 * 2 * 6, sizeof(float) * 3);
            float3[] vertices = new float3[36];
            Vector3[] srcPositions = cubeMesh.vertices;
            int[] srcTriangles = cubeMesh.triangles;
            Debug.Log("vertices(24): "+srcPositions.Length+", triangles(36): "+srcTriangles.Length);
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
            RenderTargetIdentifier[] targets = new RenderTargetIdentifier[4];
            targets[0] = emissiveTarget.colorBuffer;
            targets[1] = emissiveDxTarget.colorBuffer;
            targets[2] = emissiveDyTarget.colorBuffer;
            targets[3] = emissiveIdTarget.colorBuffer;
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
        shader.SetVector("_CameraPos", _camera.transform.position);

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
            cmdBuffer.DrawProcedural(instData[0], shader, pass, MeshTopology.Triangles, cubeMeshVertices.count, numInstances);
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

    }

    public bool updateSurfels = false;
    
    private static int instancesPerBatch = 511;// 1023 at max; limitation by Unity :/
    private Matrix4x4[] instData = new Matrix4x4[instancesPerBatch];

    private static Vector4 QuatToVec(Quaternion q){
        return new Vector4(q.x, q.y, q.z, q.w);
    }

    private void PreservePrevGBuffers(){
        Graphics.Blit(null, prevGBuff0, copyGBuffMat0);
        Graphics.Blit(null, prevGBuff1, copyGBuffMat1);
        Graphics.Blit(null, prevGBuff2, copyGBuffMat2);
        Graphics.Blit(null, prevGBuffD, copyGBuffMatD);
    }

    private void PreservePrevTransform(){
        var transform = _camera.transform;
        prevCameraPosition = transform.position;
        prevCameraRotation = QuatToVec(transform.rotation);
    }

    private void UpdateSurfelGI() {
        SurfelPathTracing();
        SurfelLightSampling();
    }

    private void SurfelPathTracing(){
        var shader = surfelTracingShader;
        shader.SetAccelerationStructure("_RaytracingAccelerationStructure", sceneRTAS);
        shader.SetInt("_FrameIndex", frameIndex);
        shader.SetVector("_CameraPosition", transform.position);
        shader.SetVector("_CameraRotation", QuatToVec(transform.rotation));
        float tan = Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        float zFactor = giTarget.height / (2.0f * tan);
        shader.SetVector("_CameraOffset", new Vector3((giTarget.width-1) * 0.5f, (giTarget.height-1) * 0.5f, zFactor));
        shader.SetTexture("_SkyBox", skyBox);
        shader.SetBuffer("_Surfels", surfels);
        shader.SetFloat("_Far", _camera.farClipPlane);
        shader.SetVector("_CameraUVSize", new Vector2((float) giTarget.width / giTarget.height * tan, tan));
        shader.SetBool("_AllowSkySurfels", allowSkySurfels);
        shader.SetBool("_AllowStrayRays", allowStrayRays);
        shader.SetShaderPass("DxrPass");
        shader.Dispatch("RaygenShader", surfels.count, 1, 1, null);
    }

    public ComputeShader surfelToAABBListShader;
    public RayTracingShader lightSamplingShader;
    private void SurfelLightSampling(){
        UpdateSurfelBounds();
        var shader = lightSamplingShader;
        if(emissiveTriangles == null){
            CollectEmissiveTriangles();
        }
        // todo calculate list of emissive triangles
        shader.SetAccelerationStructure("_RaytracingAccelerationStructure", surfelRTAS);

        // todo then use raytracing shader
        shader.SetShaderPass("DxrPass2");
        // todo use emissiveTriangles.count
        shader.Dispatch("RaygenShader", surfels.count, 1, 1, null);
    }

    public Shader emissiveDXRShader;
    private ComputeBuffer emissiveTriangles;
    private void CollectEmissiveTriangles(){

        MeshRenderer[] renderers = FindObjectsOfType<MeshRenderer>();

        int numTris = 0;
        float totalArea = 0f;
        foreach (MeshRenderer r in renderers) {
            var mat = r.sharedMaterial;
            bool isEmissive = mat != null && mat.shader == emissiveDXRShader;
            if(isEmissive) {
                MeshFilter filter = r.GetComponent<MeshFilter>();
                Color color = mat.GetColor("_Color");
                float brightness = (color.r + color.g + color.b) / 3f;
                if(filter != null && brightness > 0){
                    // calculate surface area and count triangles
                    float meshArea = 0f;
                    Mesh mesh = filter.sharedMesh;
                    Vector3[] vertices = mesh.vertices;
                    int[] triangles = mesh.triangles;
                    for(int i=0;i<triangles.Length;){
                        Vector3 a = vertices[triangles[i++]], b = vertices[triangles[i++]], c = vertices[triangles[i++]];
                        meshArea += Vector3.Cross(b-a,c-a).magnitude;
                    }
                    totalArea += meshArea * brightness;
                    numTris += triangles.Length;
                }
            }
        }
        totalArea *= 0.5f;
        numTris /= 3;

        EmissiveTriangle[] tris = new EmissiveTriangle[numTris];
        numTris = 0;
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
                    Vector3[] vertices = mesh.vertices;
                    int[] triangles = mesh.triangles;
                    for(int i=0;i<triangles.Length;){
                        Vector3 a = vertices[triangles[i++]], b = vertices[triangles[i++]], c = vertices[triangles[i++]];
                        float area = Vector3.Cross(b-a,c-a).magnitude;
                        EmissiveTriangle tri;
                        tri.posA = a;
                        tri.posB = b;
                        tri.posC = c;
                        tri.color = color3 * (area / totalArea);
                        tris[numTris++] = tri;
                    }
                }
            }
        }

        // save all triangles to compute buffer
        emissiveTriangles = new ComputeBuffer(tris.Length, UnsafeUtility.SizeOf<EmissiveTriangle>());
        emissiveTriangles.SetData(tris);

    }

    private void UpdateSurfelBounds(){
        // first update bounds
        var shader = surfelToAABBListShader;
        int kernel = shader.FindKernel("SurfelsToAABBs");
        shader.SetBuffer(kernel, "Surfels", surfels);
        shader.SetBuffer(kernel, "AABBs", surfelBounds);
        Dispatch(shader, kernel, surfels.count, 1, 1);
        surfelRTAS.Build();
    }

    private void UpdatePixelGI() {
        var shader = rayTracingShader;
        shader.SetAccelerationStructure("_RaytracingAccelerationStructure", sceneRTAS);
        shader.SetInt("_FrameIndex", frameIndex);
        shader.SetVector("_CameraPosition", transform.position);
        shader.SetVector("_CameraRotation", QuatToVec(transform.rotation));
        float tan = Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        float zFactor = giTarget.height / (2.0f * tan);
        shader.SetVector("_CameraOffset", new Vector3((giTarget.width-1) * 0.5f, (giTarget.height-1) * 0.5f, zFactor));
        shader.SetTexture("_SkyBox", skyBox);
        shader.SetTexture("_DxrTarget", giTarget);
        shader.SetShaderPass("DxrPass");
        shader.Dispatch("RaygenShader", giTarget.width, giTarget.height, 1, _camera);
    }

    private void AccumulatePixelGI(Vector3 deltaPos) {
        var shader = accuMaterial;
        shader.SetVector("_DeltaCameraPosition", deltaPos);
        shader.SetTexture("_CurrentFrame", giTarget);
        shader.SetTexture("_Accumulation", accu1);
        shader.SetInt("_FrameIndex", frameIndex);
        shader.SetTexture("prevGBuff0", prevGBuff0);
        shader.SetTexture("prevGBuff1", prevGBuff1);
        shader.SetTexture("prevGBuff2", prevGBuff2);
        shader.SetTexture("prevGBuffD", prevGBuffD);
        Graphics.Blit(giTarget, accu2, shader);
    }

    public bool useDerivatives = false;
    public int surfelPlacementIterations = 1;

    [ImageEffectOpaque]
    private void OnRenderImage(RenderTexture source, RenderTexture destination) {

        if(sleep > 0f){
            Thread.Sleep((int) (sleep * 1000));
        }

        var transform = _camera.transform;
        // Debug.Log("on-rimage: "+_camera.worldToCameraMatrix);
        if(doRT) {

            // start path tracer
            UpdatePixelGI();

            // accumulate current raytracing result
            Vector3 pos = transform.position;
            Vector3 deltaPos = pos - prevCameraPosition;
            AccumulatePixelGI(deltaPos);

            // display result on screen
            displayMaterial.SetFloat("_DivideByAlpha", 0f);
            displayMaterial.SetTexture("_SkyBox", skyBox);
            displayMaterial.SetTexture("_Accumulation", accu2);
            displayMaterial.SetFloat("_Far", _camera.farClipPlane);
            displayMaterial.SetFloat("_ShowIllumination", showIllumination ? 1f : 0f);
            displayMaterial.SetVector("_CameraPosition", pos);
            displayMaterial.SetVector("_CameraRotation", QuatToVec(transform.rotation));
            float zFactor2 = 1.0f / Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
            displayMaterial.SetVector("_CameraScale", new Vector2((zFactor2 * _camera.pixelWidth) / _camera.pixelHeight, zFactor2));
            Graphics.Blit(accu2, destination, displayMaterial);

            PreservePrevGBuffers();
            PreservePrevTransform();

            // switch accumulation textures
            var temp = accu1;
            accu1 = accu2;
            accu2 = temp;

        } else {
        
            if(updateSurfels) {
                // for faster convergence, we can use multiple iterations
                bool uds = useDerivatives;
                for(int i=0,l=surfelPlacementIterations;i<l;i++){
                    useDerivatives = uds && i == l-1;
                    DistributeSurfels();
                    AccumulateSurfelEmissions();
                }
            } else {
                AccumulateSurfelEmissions();
            }

            if(updateSurfels && surfelTracingShader != null) {
                UpdateSurfelGI();
            }

            // display result on screen
            displayMaterial.SetFloat("_DivideByAlpha", 1f);
            displayMaterial.SetTexture("_SkyBox", skyBox);
            displayMaterial.SetTexture("_Accumulation", emissiveTarget);
            displayMaterial.SetFloat("_Far", _camera.farClipPlane);
            displayMaterial.SetFloat("_ShowIllumination", showIllumination ? 1f : 0f);
            displayMaterial.SetFloat("_AllowSkySurfels", allowSkySurfels ? 1f : 0f);
            displayMaterial.SetFloat("_VisualizeSurfels", visualizeSurfels ? 1f : 0f);
            displayMaterial.SetVector("_CameraPosition", _camera.transform.position);
            displayMaterial.SetVector("_CameraRotation", QuatToVec(transform.rotation));
            float zFactor = 1.0f / Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
            displayMaterial.SetVector("_CameraScale", new Vector2((zFactor * _camera.pixelWidth) / _camera.pixelHeight, zFactor));
            Graphics.Blit(null, destination, displayMaterial);
            
            PreservePrevTransform();
            
        }

        frameIndex++;

    }

    private void OnDestroy() {
        if(sceneRTAS != null) sceneRTAS.Release();
        if(surfelRTAS != null) surfelRTAS.Release();
        DestroyTargets();
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
            surfelBounds.Release();
            surfels = null;
            surfelBounds = null;
        }
    }

    /**
     * Poisson Image Reconstruction
     */
    
    private void blur(RenderTexture src, RenderTexture tmp, RenderTexture dst){
        blurX(src, tmp);
        blurY(tmp, dst);
    }

    private void kernel(RenderTexture src, RenderTexture dst, int dx, int dy, Material material) {
        material.SetVector("_DeltaUV", new Vector2(dx / (src.width-1), dy / (src.height-1)));
        Graphics.Blit(src, dst, material);
    }

    private void blurX(RenderTexture src, RenderTexture dst) {
        kernel(src, dst, 1, 0, unsignedBlurMaterial);
    }

    private void blurY(RenderTexture src, RenderTexture dst) {
        kernel(src, dst, 0, 1, unsignedBlurMaterial);
    }

    private void blurXSigned(RenderTexture src, RenderTexture dst) {
        kernel(src, dst, 1, 0, signedBlurMaterial);
    }

    private void blurYSigned(RenderTexture src, RenderTexture dst) {
        kernel(src, dst, 0, 1, signedBlurMaterial);
    }

    private void poissonIterate(RenderTexture src, RenderTexture dst, RenderTexture dx, RenderTexture dy, RenderTexture blurred) {
        var shader = poissonMaterial;
        float dxf = 1f/(src.width-1), dyf = 1f/(src.height-1);
        shader.SetVector("_Dx1", new Vector2(1*dxf, 0f));
        shader.SetVector("_Dx2", new Vector2(2*dxf, 0f));
        shader.SetVector("_Dy1", new Vector2(0f, 1*dyf));
        shader.SetVector("_Dy2", new Vector2(0f, 2*dyf));
        shader.SetTexture("_Src", src);
        shader.SetTexture("_Dx", dx);
        shader.SetTexture("_Dy", dy);
        shader.SetTexture("_Blurred", blurred);
        Graphics.Blit(null, dst, shader);
    }

    private void add(RenderTexture a, RenderTexture b, RenderTexture c, RenderTexture dst) {
        var shader = addMaterial;
        shader.SetTexture("_TexA", a);
        shader.SetTexture("_TexB", b);
        shader.SetTexture("_TexC", c);
        Graphics.Blit(null, dst, shader);
    }

    public int poissonBlurRadius = 25;
    private int numPoissonIterations = 10;
    private RenderTexture blurred, bdx, bdy, res0;
    public Shader blurShader;
    private float[] unsignedBlurMask, signedBlurMask;
    public Material poissonMaterial, addMaterial;
    private Material signedBlurMaterial, unsignedBlurMaterial;
    private float gaussianWeight(int i, float n, float sigma){ // gaussian bell curve with standard deviation <sigma> from -<n> to <n>
        float x = i * sigma / (n-1);
        return Mathf.Exp(-x*x);
    }
    private RenderTexture poissonReconstruct(RenderTexture src, RenderTexture dx, RenderTexture dy) {

        if(signedBlurMaterial == null){
            if(blurShader == null){
                Debug.Log("Blur Shader is missing!");
                return src;
            }
            signedBlurMaterial = new Material(blurShader);
            unsignedBlurMaterial = new Material(blurShader);
        }

        if(unsignedBlurMask == null || unsignedBlurMask.Length != poissonBlurRadius * 2 + 1){
            // create blur masks
            float sigma = 2.5f;
            unsignedBlurMask = new float[poissonBlurRadius * 2 + 1];
            signedBlurMask = new float[poissonBlurRadius * 2 + 1];
            float weightSum = 0f;
            int n = Mathf.Max(poissonBlurRadius, 1);
            for(int i=0;i<=poissonBlurRadius;i++){
                weightSum += gaussianWeight(i, n, sigma);
            }
            float weightScale = 1f / weightSum;
            for(int i=0;i<=poissonBlurRadius;i++){
                float weight = weightScale * gaussianWeight(i, n, sigma);
                int j = i + poissonBlurRadius;
                unsignedBlurMask[i] = unsignedBlurMask[j] = weight;
                signedBlurMask[i] = -weight;
                signedBlurMask[j] = +weight;
            }
            signedBlurMask[poissonBlurRadius] = 0; // blur mask must be symmetric
            signedBlurMaterial.SetInt("_N", poissonBlurRadius);
            signedBlurMaterial.SetFloatArray("_Weights", signedBlurMask);
            unsignedBlurMaterial.SetInt("_N", poissonBlurRadius);
            unsignedBlurMaterial.SetFloatArray("_Weights", unsignedBlurMask);
        }

        if(addMaterial == null){
            Debug.Log("AddMaterial is missing!");
            return src;
        } else if(poissonMaterial == null){
            Debug.Log("PoissonMaterial is missing!");
            return src;
        }

        RenderTexture tmp = bdx;
        blur(src, tmp, blurred);
        blurXSigned(dx, bdx);
        blurYSigned(dy, bdy);
        add(blurred, bdx, bdy, res0);
        RenderTexture res1 = bdx;
        for(int i=0;i<numPoissonIterations;i++){

            poissonIterate(res0, res1, dx, dy, blurred);

             tmp = res0;
            res0 = res1;
            res1 = tmp;
        }
        return res0;
    }

}