using UnityEngine;
using UnityEngine.Experimental.Rendering;

public class DXRCamera : MonoBehaviour {
    public Color SkyColor = Color.blue;
    public Color GroundColor = Color.gray;

    private Camera _camera;
    // target texture for raytracing
    private RenderTexture dxrTarget;
    // textures for accumulation
    private RenderTexture accumulationTarget1;
    private RenderTexture accumulationTarget2;

    // scene structure for raytracing
    private RayTracingAccelerationStructure rtas;

    // raytracing shader
    public RayTracingShader rayTracingShader;
    // helper material to accumulate raytracing results
    private Material accumulationMaterial;

    private Matrix4x4 cameraWorldMatrix;

    private int frameIndex;

    private void Start() {

        _camera = GetComponent<Camera>();

        CreateTargets();

        // build scene for raytracing
        InitRaytracingAccelerationStructure();

        LoadShader();

        // update raytracing parameters
        UpdateParameters();

        accumulationMaterial = new Material(Shader.Find("Hidden/Accumulation"));
    }

	private void LoadShader() {

		// rayTracingShader = Resources.Load<RayTracingShader>("RayTracingShader");

        rayTracingShader.SetAccelerationStructure("_RaytracingAccelerationStructure", rtas);
        rayTracingShader.SetTexture("_DxrTarget", dxrTarget);
        // set shader pass name that will be used during raytracing
        rayTracingShader.SetShaderPass("DxrPass");

	}

	private void CreateTargets() {

		dxrTarget = new RenderTexture(_camera.pixelWidth, _camera.pixelHeight, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Default);
        dxrTarget.enableRandomWrite = true;
        dxrTarget.Create();

        accumulationTarget1 = new RenderTexture(dxrTarget);
        accumulationTarget2 = new RenderTexture(dxrTarget);

	}

    private void Update() {
        // update parameters if camera moved
        if (cameraWorldMatrix != _camera.transform.localToWorldMatrix || Input.GetKeyDown(KeyCode.Space)) {
            UpdateParameters();
        }
    }

    private void UpdateParameters() {

		if(rtas == null) {
			InitRaytracingAccelerationStructure();
		}

        // update raytracing scene, in case something moved
        rtas.Build();

        // frustum corners for current camera transform
        Vector3 bottomLeft = _camera.ViewportToWorldPoint(new Vector3(0, 0, _camera.farClipPlane)).normalized;
        Vector3 topLeft = _camera.ViewportToWorldPoint(new Vector3(0, 1, _camera.farClipPlane)).normalized;
        Vector3 bottomRight = _camera.ViewportToWorldPoint(new Vector3(1, 0, _camera.farClipPlane)).normalized;
        Vector3 topRight = _camera.ViewportToWorldPoint(new Vector3(1, 1, _camera.farClipPlane)).normalized;

        // update camera, environment parameters
        rayTracingShader.SetVector("_SkyColor", SkyColor.gamma);
        rayTracingShader.SetVector("_GroundColor", GroundColor.gamma);

        rayTracingShader.SetVector("_TopLeftFrustumDir", topLeft);
        rayTracingShader.SetVector("_TopRightFrustumDir", topRight);
        rayTracingShader.SetVector("_BottomLeftFrustumDir", bottomLeft);
        rayTracingShader.SetVector("_BottomRightFrustumDir", bottomRight);

        rayTracingShader.SetVector("_CameraPos", _camera.transform.position);

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

    [ImageEffectOpaque]
    private void OnRenderImage(RenderTexture source, RenderTexture destination) {
        // update frame index and start path tracer
        rayTracingShader.SetInt("_FrameIndex", frameIndex);
        // start one thread for each pixel on screen
        rayTracingShader.Dispatch("MyRaygenShader", dxrTarget.width, dxrTarget.height, 1, _camera);

        // update accumulation material
        accumulationMaterial.SetTexture("_CurrentFrame", dxrTarget);
        accumulationMaterial.SetTexture("_Accumulation", accumulationTarget1);
        accumulationMaterial.SetInt("_FrameIndex", frameIndex++);

        // accumulate current raytracing result
        Graphics.Blit(dxrTarget, accumulationTarget2, accumulationMaterial);
        // display result on screen
        Graphics.Blit(accumulationTarget2, destination);

        // switch accumulate textures
        var temp = accumulationTarget1;
        accumulationTarget1 = accumulationTarget2;
        accumulationTarget2 = temp;
    }

    private void OnGUI() {
        // display samples per pixel
        GUILayout.Label("SPP: " + frameIndex);
    }

    private void OnDestroy() {
        // cleanup
        rtas.Release();
        dxrTarget.Release();
        accumulationTarget1.Release();
        accumulationTarget2.Release();
    }
}