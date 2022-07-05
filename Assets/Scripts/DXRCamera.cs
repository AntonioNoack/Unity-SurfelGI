using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using Unity.Mathematics; // float4x3, float3
using Unity.Collections.LowLevel.Unsafe; // for sizeof(struct)

public class DXRCamera : MonoBehaviour {

    struct Surfel {
        float4 position;
        float4 rotation;
        float4 color;
    };

    public float surfelDensity = 2f;

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

    private Vector3 previousCameraPosition;

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
        
        var camTransform = _camera.transform;
        shader.SetVector("_CameraPosition", camTransform.position);
        
        var rotation = camTransform.rotation;
        shader.SetVector("_CameraRotation", new Vector4(rotation.x, rotation.y, rotation.z, rotation.w));
        
        float invZFactor = 1f / Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        shader.SetVector("_CameraUVScale", new Vector2(((float)giTarget.height / (giTarget.width)) * invZFactor, invZFactor));

        float zFactor = giTarget.height / (2.0f * Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad));
        shader.SetVector("_CameraOffset", new Vector3((giTarget.width-1) * 0.5f, (giTarget.height-1) * 0.5f, zFactor));

        shader.SetVector("_ZBufferParams", Shader.GetGlobalVector("_ZBufferParams"));
        
        for(int i = 0; i < (hasPlacedSurfels ? 2 : 1) ; i++){

            bool screenSpaceDist = i > 0;

            int kernel = PrepareDistribution(shader, screenSpaceDist, depthTex);
            if(kernel < 0) continue;

            uint gsx, gsy, gsz;
            shader.SetBuffer(kernel, "Surfels", surfels);
            shader.GetKernelThreadGroupSizes(kernel, out gsx, out gsy, out gsz);
            
            if(screenSpaceDist) {
                shader.Dispatch(kernel, CeilDiv(giTarget.width, (int) gsx * 16), CeilDiv(giTarget.height, (int) gsy * 16), 1);
            } else {
                shader.Dispatch(kernel, CeilDiv(surfels.count, (int) gsx), 1, 1);
            }

        }

        hasPlacedSurfels = true;

    }

    int PrepareDistribution(ComputeShader shader, bool screenSpaceDist, Texture depthTex){
        
        int kernel = shader.FindKernel(hasPlacedSurfels ? (
            screenSpaceDist ? "UpdateSurfelDistribution2" : "UpdateSurfelDistribution"
        ) : "InitSurfelDistribution");

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

        if(hasPlacedSurfels && screenSpaceDist) {
            shader.SetTexture(kernel, "_Weights", emissiveTarget);
        }

        uint gsx, gsy, gsz;
        shader.SetBuffer(kernel, "Surfels", surfels);
        shader.GetKernelThreadGroupSizes(kernel, out gsx, out gsy, out gsz);
        
        if(screenSpaceDist) {
            shader.Dispatch(kernel, CeilDiv(giTarget.width, (int) gsx * 16), CeilDiv(giTarget.height, (int) gsy * 16), 1);
        } else {
            shader.Dispatch(kernel, CeilDiv(surfels.count, (int) gsx), 1, 1);
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
        DistributeSurfels();
        RenderEmissiveTexture();
    }

    private void UpdateParameters() {
		if(rtas == null) {
			InitRaytracingAccelerationStructure();
		}
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
        // render sky
        if(skyBoxCamera != null) skyBoxCamera.RenderToCubemap(skyBox, -1);
        else Debug.Log("Missing skybox camera");
    }

    public Mesh cubeMesh;
    public Material surfelMaterial;
    public bool doRT = false;

    private CommandBuffer cmdBuffer = null;

    private ComputeBuffer countBuffer;

    void RenderEmissiveTexture(){

        if(!hasPlacedSurfels){
            Debug.Log("Waiting for surfels to be placed");
            return;
        }

        if(cubeMesh == null || surfelMaterial == null){
            Debug.Log("Missing surfel "+(
                cubeMesh == null ? 
                    surfelMaterial == null ? "mesh and material" :
                    "mesh" : "material"
            ));
            return;
        }


        if(cmdBuffer == null) {
            Debug.Log("Creating new command buffer");
            cmdBuffer = new CommandBuffer();
            cmdBuffer.name = "Surfel Emission";
            countBuffer = new ComputeBuffer(5, 4, ComputeBufferType.IndirectArguments); // element count, stride in bytes
            uint[] data = new uint[4];
            int subMeshIndex = 0;
            data[0] = (uint) cubeMesh.GetIndexCount(subMeshIndex);
            data[1] = (uint) instancesPerBatch;
            data[2] = (uint) cubeMesh.GetIndexStart(subMeshIndex);
            data[3] = (uint) cubeMesh.GetBaseVertex(subMeshIndex);
            countBuffer.SetData(data);
            _camera.AddCommandBuffer(CameraEvent.AfterGBuffer, cmdBuffer);
        }

        // surfelMaterial.SetMatrix("_InvViewMatrix", _camera.worldToCameraMatrix.inverse);
        // surfelMaterial.SetMatrix("_InvProjectionMatrix", _camera.projectionMatrix.inverse);
        float fy = Mathf.Tan(_camera.fieldOfView*Mathf.Deg2Rad*0.5f);
        surfelMaterial.SetVector("_FieldOfViewFactor", new Vector2(fy*_camera.pixelWidth/_camera.pixelHeight, fy));

        cmdBuffer.Clear(); // clear all commands
        cmdBuffer.SetRenderTarget(emissiveTarget);



        // https://docs.unity3d.com/ScriptReference/Rendering.CommandBuffer.SetViewProjectionMatrices.html
        cmdBuffer.SetViewProjectionMatrices(_camera.worldToCameraMatrix, _camera.projectionMatrix);
        cmdBuffer.ClearRenderTarget(true, true, Color.clear, 1f);// depth, color, color-value, depth-value (default is 1)

        // todo copy original depth into their depth for better performance
        // RenderTexture prev = RenderTexture.active;
        // if(changeRT) Graphics.SetRenderTarget(emissiveTarget);
        // todo define/update surfel positions by previous emissiveTarget density
        
        

        surfelMaterial.SetBuffer("_Surfels", surfels);        
        cmdBuffer.SetGlobalFloat("_SurfelCount", surfels.count);

        int numInstances = surfels.count;
        int pass = -1; // surfelMaterial.FindPass(""); // which shader pass, or -1 for all
        int offset = 0;
        while(numInstances > 0){
            cmdBuffer.SetGlobalFloat("_InstanceIDOffset", offset);
            cmdBuffer.DrawMeshInstanced(cubeMesh, 0, surfelMaterial, pass, instData);
            numInstances -= instancesPerBatch;
            offset += instancesPerBatch;
        }
        

        // cmdBuffer.DrawMeshInstancedIndirect(cubeMesh, 0, surfelMaterial, pass, countBuffer, 0);

        // Graphics.ExecuteCommandBuffer(cmdBuffer);
    }

    public bool updateSurfels = false;
    
    private static int instancesPerBatch = 512;// 1023 at max; limitation by Unity :/
    private Matrix4x4[] instData = new Matrix4x4[instancesPerBatch];

    [ImageEffectOpaque]
    private void OnRenderImage(RenderTexture source, RenderTexture destination) {

        if(doRT){

            // update frame index and start path tracer
            rayTracingShader.SetInt("_FrameIndex", frameIndex);
            rayTracingShader.SetVector("_CameraPosition", _camera.transform.position);
            var rotation = _camera.transform.rotation;
            rayTracingShader.SetVector("_CameraRotation", new Vector4(rotation.x, rotation.y, rotation.z, rotation.w));
            float zFactor1 = giTarget.height / (2.0f * Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad));
            rayTracingShader.SetVector("_CameraOffset", new Vector3((giTarget.width-1) * 0.5f, (giTarget.height-1) * 0.5f, zFactor1));

            rayTracingShader.SetTexture("_SkyBox", skyBox);
            rayTracingShader.SetTexture("_DxrTarget", giTarget);
            rayTracingShader.SetShaderPass("DxrPass");
            rayTracingShader.Dispatch("RaygenShader", giTarget.width, giTarget.height, 1, _camera);

            // update accumulation material
            Vector3 pos = _camera.transform.position;
            Vector3 deltaPos = pos - previousCameraPosition;
            previousCameraPosition = pos;
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
            // displayMaterial.SetVector("_CameraPosition", pos);
            displayMaterial.SetVector("_CameraRotation", new Vector4(rotation.x, rotation.y, rotation.z, rotation.w));
            float zFactor2 = 1.0f / Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
            displayMaterial.SetVector("_CameraScale", new Vector2((zFactor2 * _camera.pixelWidth) / _camera.pixelHeight, zFactor2));
            Graphics.Blit(accu2, destination, displayMaterial);

            Graphics.Blit(null, prevGBuff0, copyGBuffMat0);
            Graphics.Blit(null, prevGBuff1, copyGBuffMat1);
            Graphics.Blit(null, prevGBuff2, copyGBuffMat2);
            Graphics.Blit(null, prevGBuffD, copyGBuffMatD);

            // switch accumulate textures
            var temp = accu1;
            accu1 = accu2;
            accu2 = temp;

        } else {

            var rotation = _camera.transform.rotation;
            if(updateSurfels && surfelTracingShader != null) {
                surfelTracingShader.SetInt("_FrameIndex", frameIndex);
                surfelTracingShader.SetVector("_CameraPosition", _camera.transform.position);
                surfelTracingShader.SetVector("_CameraRotation", new Vector4(rotation.x, rotation.y, rotation.z, rotation.w));
                float tan = Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
                float zFactor1 = giTarget.height / (2.0f * tan);
                surfelTracingShader.SetVector("_CameraOffset", new Vector3((giTarget.width-1) * 0.5f, (giTarget.height-1) * 0.5f, zFactor1));
                surfelTracingShader.SetTexture("_SkyBox", skyBox);
                surfelTracingShader.SetBuffer("_Surfels", surfels);
                surfelTracingShader.SetFloat("_Far", _camera.farClipPlane);
                surfelTracingShader.SetVector("_CameraUVSize", new Vector2((float) giTarget.width / giTarget.height * tan, tan));
                surfelTracingShader.SetShaderPass("DxrPass");
                surfelTracingShader.Dispatch("RaygenShader", surfels.count, 1, 1, null);
            }

            // display result on screen
            displayMaterial.SetFloat("_DivideByAlpha", 1f);
            displayMaterial.SetTexture("_SkyBox", skyBox);
            displayMaterial.SetTexture("_Accumulation", emissiveTarget);
            displayMaterial.SetFloat("_Far", _camera.farClipPlane);
            // displayMaterial.SetVector("_CameraPosition", pos);
            displayMaterial.SetVector("_CameraRotation", new Vector4(rotation.x, rotation.y, rotation.z, rotation.w));
            float zFactor = 1.0f / Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
            displayMaterial.SetVector("_CameraScale", new Vector2((zFactor * _camera.pixelWidth) / _camera.pixelHeight, zFactor));
            Graphics.Blit(null, destination, displayMaterial);

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