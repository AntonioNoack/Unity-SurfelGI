using UnityEngine;
using UnityEngine.Experimental.Rendering;

public class DXRCamera : MonoBehaviour {
    
    public Color SkyColor = Color.blue;
    public Color GroundColor = Color.gray;

    public float Exposure = 1f;

    private Camera _camera;
    // target texture for raytracing
    private RenderTexture giTarget;
    // textures for accumulation
    private RenderTexture accu1;
    private RenderTexture accu2;

    // scene structure for raytracing
    private RayTracingAccelerationStructure rtas;

    // raytracing shader
    public RayTracingShader rayTracingShader;
    // helper material to accumulate raytracing results
    private Material accuMaterial, displayMaterial;

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

        accuMaterial = new Material(Shader.Find("Hidden/Accumulation"));
        displayMaterial = new Material(Shader.Find("Hidden/Display"));
    }

	private void LoadShader() {
        rayTracingShader.SetAccelerationStructure("_RaytracingAccelerationStructure", rtas);
	}

	private void CreateTargets() {

		giTarget = new RenderTexture(_camera.pixelWidth, _camera.pixelHeight, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Default);
        giTarget.enableRandomWrite = true;
        giTarget.Create();

        accu1 = new RenderTexture(giTarget);
        accu2 = new RenderTexture(giTarget);

	}

    private void DestroyTargets(){
        giTarget.Release();
        accu1.Release();
        accu2.Release();
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
    }

    private void UpdateParameters() {

		if(rtas == null) {
			InitRaytracingAccelerationStructure();
		}

        // update raytracing scene, in case something moved
        rtas.Build();

        // update camera, environment parameters
        rayTracingShader.SetVector("_SkyColor", SkyColor.gamma);
        rayTracingShader.SetVector("_GroundColor", GroundColor.gamma);

        rayTracingShader.SetVector("_CameraPosition", _camera.transform.position);
        var rotation = _camera.transform.rotation;
        rayTracingShader.SetVector("_CameraRotation", new Vector4(rotation.x, rotation.y, rotation.z, rotation.w));
        float zFactor = giTarget.height / (2.0f * Mathf.Tan(_camera.fieldOfView * 0.5f * Mathf.Deg2Rad));
        rayTracingShader.SetVector("_CameraOffset", new Vector3(giTarget.width * 0.5f, giTarget.height * 0.5f, zFactor));

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
        rayTracingShader.SetTexture("_DxrTarget", giTarget);
        rayTracingShader.SetShaderPass("DxrPass");
        rayTracingShader.Dispatch("RaygenShader", giTarget.width, giTarget.height, 1, _camera);
        
        // update accumulation material
        accuMaterial.SetTexture("_CurrentFrame", giTarget);
        accuMaterial.SetTexture("_Accumulation", accu1);
        accuMaterial.SetInt("_FrameIndex", frameIndex++);

        // accumulate current raytracing result
        Graphics.Blit(giTarget, accu2, accuMaterial);

        // display result on screen
        displayMaterial.SetFloat("_Exposure", Exposure);
        displayMaterial.SetTexture("_Accumulation", accu2);
        Graphics.Blit(accu2, destination, displayMaterial);

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