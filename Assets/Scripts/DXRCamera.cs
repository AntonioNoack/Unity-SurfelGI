using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using Unity.Mathematics; // float4x3, float3
using Unity.Collections.LowLevel.Unsafe; // for sizeof(struct)
using System.Threading; // sleep for manual fps limit

public class DXRCamera : MonoBehaviour {

    struct Surfel {
        float4 position;
        float4 rotation;
        float4 color;
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
    private ComputeBuffer surfels;
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
    private RenderTexture emissiveTarget;

    // scene structure for raytracing
    private RayTracingAccelerationStructure rtas;

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

        LoadShader();

        // update raytracing parameters
        UpdateParameters();

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

    private void DistributeSurfels() {

        var shader = surfelDistShader;
        if(shader == null) Debug.Log("Missing surfel shader!");
        if(surfels == null) {
            surfels = new ComputeBuffer(maxNumSurfels, UnsafeUtility.SizeOf<Surfel>());
            Debug.Log("created surfel compute buffer, "+surfels.count);
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
        shader.SetFloat("_FrameIndex", frameIndex);
        shader.SetBool("_AllowSkySurfels", allowSkySurfels);
        
        var transform = _camera.transform;
        shader.SetVector("_CameraPosition", usePrevFrameForDistribution ? prevCameraPosition : transform.position);
        shader.SetVector("_CameraRotation", usePrevFrameForDistribution ? prevCameraRotation : QuatToVec(transform.rotation));
        
        float invZFactor = 1f / Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        shader.SetVector("_CameraUVScale", new Vector2(((float)giTarget.height / (giTarget.width)) * invZFactor, invZFactor));

        float zFactor = giTarget.height / (2.0f * Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad));
        shader.SetVector("_CameraOffset", new Vector3((giTarget.width-1) * 0.5f, (giTarget.height-1) * 0.5f, zFactor));

        shader.SetVector("_ZBufferParams", Shader.GetGlobalVector("_ZBufferParams"));

        for(int i = 0; i < (hasPlacedSurfels ? 2 : 1) ; i++){

            bool screenSpace = i > 0;

            int kernel = PrepareDistribution(shader, screenSpace, depthTex);
            if(kernel < 0) continue;

            uint gsx, gsy, gsz;
            shader.SetBuffer(kernel, "Surfels", surfels);
            shader.GetKernelThreadGroupSizes(kernel, out gsx, out gsy, out gsz);
            
            if(screenSpace) {
                shader.Dispatch(kernel, CeilDiv(giTarget.width, (int) gsx * 16), CeilDiv(giTarget.height, (int) gsy * 16), 1);
            } else {
                shader.Dispatch(kernel, CeilDiv(surfels.count, (int) gsx), 1, 1);
            }

        }

        hasPlacedSurfels = true;

    }

    public bool usePrevFrameForDistribution = false;

    private int PrepareDistribution(ComputeShader shader, bool screenSpace, Texture depthTex){
        
        int kernel = shader.FindKernel(
            hasPlacedSurfels ? 
                screenSpace ? 
                    "SpawnSurfelsInGaps" : 
                    "DiscardSmallAndLargeSurfels" :
                "InitSurfelDistribution"
        );

        if(usePrevFrameForDistribution){

            shader.SetTexture(kernel, "_CameraGBufferTexture0", prevGBuff0);
            shader.SetTexture(kernel, "_CameraGBufferTexture1", prevGBuff1);
            shader.SetTexture(kernel, "_CameraGBufferTexture2", prevGBuff2);
            shader.SetTexture(kernel, "_CameraDepthTexture",    prevGBuffD);

        } else {

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

        }

        if(emissiveTarget != null) {
            shader.SetTexture(kernel, "_Weights", emissiveTarget);
        }

        return kernel;

    }

    private void EnableMotionVectors(){
        _camera.depthTextureMode |= DepthTextureMode.Depth | DepthTextureMode.MotionVectors;
    }

	private void LoadShader() {
        rayTracingShader.SetAccelerationStructure("_RaytracingAccelerationStructure", rtas);
        surfelTracingShader.SetAccelerationStructure("_RaytracingAccelerationStructure", rtas);
	}

	private void CreateTargets() {

        int width = _camera.pixelWidth, height = _camera.pixelHeight;

		giTarget = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Default);
        giTarget.enableRandomWrite = true;
        giTarget.Create();

        accu1 = new RenderTexture(giTarget);
        accu2 = new RenderTexture(giTarget);

        prevGBuff0 = new RenderTexture(width, height, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Default);
        prevGBuff1 = new RenderTexture(width, height, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Default);
        prevGBuff2 = new RenderTexture(width, height, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Default);
        prevGBuffD = new RenderTexture(width, height, 0, RenderTextureFormat.RFloat, RenderTextureReadWrite.Default);

        emissiveTarget = new RenderTexture(width, height, 0, RenderTextureFormat.ARGBHalf, RenderTextureReadWrite.Default);
        emissiveTarget.enableRandomWrite = true;
        emissiveTarget.Create();

        prevGBuff0.enableRandomWrite = true;
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

    private void UpdateParameters() {
		if(rtas == null) InitRaytracingAccelerationStructure();
        // update raytracing scene, in case something moved
        rtas.Build();
    }

    private void InitRaytracingAccelerationStructure() {
        RayTracingAccelerationStructure.RASSettings settings = new RayTracingAccelerationStructure.RASSettings();
        // include all layers
        settings.layerMask = ~0;
        // enable automatic updates
        settings.managementMode = RayTracingAccelerationStructure.ManagementMode.Automatic;
        // include all renderer types
        settings.rayTracingModeMask = RayTracingAccelerationStructure.RayTracingModeMask.Everything;
        rtas = new RayTracingAccelerationStructure(settings);
        // collect all objects in scene and add them to raytracing scene
        Renderer[] renderers = FindObjectsOfType<Renderer>();
        foreach (Renderer r in renderers)
            rtas.AddInstance(r);
            
        // build raytrasing scene
        rtas.Build();
    }

    private void RenderSky(){
        if(skyBoxCamera != null) skyBoxCamera.RenderToCubemap(skyBox, -1);
        else Debug.Log("Missing skybox camera");
    }

    public Mesh cubeMesh;
    public Material surfelMaterial, surfelProcMaterial;
    public bool doRT = false;

    private CommandBuffer cmdBuffer = null;

    private ComputeBuffer countBuffer;

    private ComputeBuffer cubeMeshVertices;

    public bool useProceduralSurfels = false;

    void AccumulateSurfelEmissions() {

        Material shader = useProceduralSurfels ? surfelProcMaterial : surfelMaterial;

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

        bool firstFrame = false;
        if(cmdBuffer == null) {
            firstFrame = true;
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

        // if(!firstFrame) return; // command buffer doesn't change, only a few shader variables

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

    private void PreservePrevState(){
        Graphics.Blit(null, prevGBuff0, copyGBuffMat0);
        Graphics.Blit(null, prevGBuff1, copyGBuffMat1);
        Graphics.Blit(null, prevGBuff2, copyGBuffMat2);
        Graphics.Blit(null, prevGBuffD, copyGBuffMatD);
        var transform = _camera.transform;
        prevCameraPosition = transform.position;
        prevCameraRotation = QuatToVec(transform.rotation);
    }

    [ImageEffectOpaque]
    private void OnRenderImage(RenderTexture source, RenderTexture destination) {

        if(sleep > 0f){
            Thread.Sleep((int) (sleep * 1000));
        }
        
        DistributeSurfels();
        AccumulateSurfelEmissions();

        var transform = _camera.transform;
        // Debug.Log("on-rimage: "+_camera.worldToCameraMatrix);
        if(doRT){

            // update frame index and start path tracer
            rayTracingShader.SetInt("_FrameIndex", frameIndex);
            rayTracingShader.SetVector("_CameraPosition", transform.position);
            rayTracingShader.SetVector("_CameraRotation", QuatToVec(transform.rotation));
            float zFactor1 = giTarget.height / (2.0f * Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad));
            rayTracingShader.SetVector("_CameraOffset", new Vector3((giTarget.width-1) * 0.5f, (giTarget.height-1) * 0.5f, zFactor1));

            rayTracingShader.SetTexture("_SkyBox", skyBox);
            rayTracingShader.SetTexture("_DxrTarget", giTarget);
            rayTracingShader.SetShaderPass("DxrPass");
            rayTracingShader.Dispatch("RaygenShader", giTarget.width, giTarget.height, 1, _camera);

            // update accumulation material
            Vector3 pos = transform.position;
            Vector3 deltaPos = pos - prevCameraPosition;
            accuMaterial.SetVector("_DeltaCameraPosition", deltaPos);
            accuMaterial.SetTexture("_CurrentFrame", giTarget);
            accuMaterial.SetTexture("_Accumulation", accu1);
            accuMaterial.SetInt("_FrameIndex", frameIndex);

            // accumulate current raytracing result
            accuMaterial.SetTexture("prevGBuff0", prevGBuff0);
            accuMaterial.SetTexture("prevGBuff1", prevGBuff1);
            accuMaterial.SetTexture("prevGBuff2", prevGBuff2);
            accuMaterial.SetTexture("prevGBuffD", prevGBuffD);
            Graphics.Blit(giTarget, accu2, accuMaterial);

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

            PreservePrevState();

            // switch accumulate textures
            var temp = accu1;
            accu1 = accu2;
            accu2 = temp;

        } else {

            if(updateSurfels && surfelTracingShader != null) {
                surfelTracingShader.SetInt("_FrameIndex", frameIndex);
                surfelTracingShader.SetVector("_CameraPosition", transform.position);
                surfelTracingShader.SetVector("_CameraRotation", QuatToVec(transform.rotation));
                float tan = Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
                float zFactor1 = giTarget.height / (2.0f * tan);
                surfelTracingShader.SetVector("_CameraOffset", new Vector3((giTarget.width-1) * 0.5f, (giTarget.height-1) * 0.5f, zFactor1));
                surfelTracingShader.SetTexture("_SkyBox", skyBox);
                surfelTracingShader.SetBuffer("_Surfels", surfels);
                surfelTracingShader.SetFloat("_Far", _camera.farClipPlane);
                surfelTracingShader.SetVector("_CameraUVSize", new Vector2((float) giTarget.width / giTarget.height * tan, tan));
                surfelTracingShader.SetBool("_AllowSkySurfels", allowSkySurfels);
                surfelTracingShader.SetBool("_AllowStrayRays", allowStrayRays);
                surfelTracingShader.SetShaderPass("DxrPass");
                surfelTracingShader.Dispatch("RaygenShader", surfels.count, 1, 1, null);
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
            
            PreservePrevState();

        }

        frameIndex++;

    }

    private void OnGUI() {
        // display samples per pixel
        GUILayout.Label("SPP: " + frameIndex);
    }

    private void OnDestroy() {
        if(rtas != null) rtas.Release();
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
            surfels = null;
        }
    }
}