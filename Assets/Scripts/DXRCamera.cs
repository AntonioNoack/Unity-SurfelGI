using UnityEngine;
using UnityEngine.Experimental.Rendering;

public class DXRCamera : MonoBehaviour {
    
    public Color SkyColor = Color.blue;
    public Color GroundColor = Color.gray;

    private Camera _camera;
    // target texture for raytracing
    private RenderTexture giTarget;
    // textures for accumulation
    private RenderTexture accu1;
    private RenderTexture accu2;

    private RenderTexture prevGBuff0, prevGBuff1, prevGBuff2, prevGBuffD;

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

    }

    private void EnableMotionVectors(){
        _camera.depthTextureMode |= DepthTextureMode.Depth | DepthTextureMode.MotionVectors;
    }

	private void LoadShader() {
        rayTracingShader.SetAccelerationStructure("_RaytracingAccelerationStructure", rtas);
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
        // skyBox.Release(); // not supported???
    }

    private void Update() {
        if(_camera.pixelWidth != giTarget.width || _camera.pixelHeight != giTarget.height){
            DestroyTargets();
            CreateTargets();
            frameIndex = 0;
        }
        // update parameters if camera moved
        if (cameraWorldMatrix != _camera.transform.localToWorldMatrix || Input.GetKeyDown(KeyCode.Space)) {
            UpdateParameters();
        }
        if(needsSkyBoxUpdate){
            RenderSky();
            needsSkyBoxUpdate = false;
        }
    }

    private void UpdateParameters() {

		if(rtas == null) {
			InitRaytracingAccelerationStructure();
		}

        // update raytracing scene, in case something moved
        rtas.Build();

        // update camera
        rayTracingShader.SetVector("_CameraPosition", _camera.transform.position);
        var rotation = _camera.transform.rotation;
        rayTracingShader.SetVector("_CameraRotation", new Vector4(rotation.x, rotation.y, rotation.z, rotation.w));
        float zFactor = giTarget.height / (2.0f * Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad));
        rayTracingShader.SetVector("_CameraOffset", new Vector3((giTarget.width-1) * 0.5f, (giTarget.height-1) * 0.5f, zFactor));

        cameraWorldMatrix = _camera.transform.localToWorldMatrix;

        // reset accumulation frame counter
        frameIndex = 0;
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

    [ImageEffectOpaque]
    private void OnRenderImage(RenderTexture source, RenderTexture destination) {

        // update frame index and start path tracer
        rayTracingShader.SetInt("_FrameIndex", frameIndex);
        // start one thread for each pixel on screen
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
        accuMaterial.SetInt("_FrameIndex", frameIndex++);

        // accumulate current raytracing result
        accuMaterial.SetTexture("prevGBuff0", prevGBuff0);
        accuMaterial.SetTexture("prevGBuff1", prevGBuff1);
        accuMaterial.SetTexture("prevGBuff2", prevGBuff2);
        accuMaterial.SetTexture("prevGBuffD", prevGBuffD);
        Graphics.Blit(giTarget, accu2, accuMaterial);

        // display result on screen
        displayMaterial.SetTexture("_SkyBox", skyBox);
        displayMaterial.SetTexture("_Accumulation", accu2);
        displayMaterial.SetFloat("_Far", _camera.farClipPlane);
        // displayMaterial.SetVector("_CameraPosition", pos);
        var rotation = _camera.transform.rotation;
        displayMaterial.SetVector("_CameraRotation", new Vector4(rotation.x, rotation.y, rotation.z, rotation.w));
        float zFactor = 1.0f / Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        displayMaterial.SetVector("_CameraScale", new Vector2((zFactor * _camera.pixelWidth) / _camera.pixelHeight, zFactor));
        Graphics.Blit(accu2, destination, displayMaterial);

        Graphics.Blit(null, prevGBuff0, copyGBuffMat0);
        Graphics.Blit(null, prevGBuff1, copyGBuffMat1);
        Graphics.Blit(null, prevGBuff2, copyGBuffMat2);
        Graphics.Blit(null, prevGBuffD, copyGBuffMatD);

        // switch accumulate textures
        var temp = accu1;
        accu1 = accu2;
        accu2 = temp;

    }

    private void OnGUI() {
        // display samples per pixel
        GUILayout.Label("SPP: " + frameIndex);
    }

    private void OnDestroy() {
        rtas.Release();
        DestroyTargets();
    }
}