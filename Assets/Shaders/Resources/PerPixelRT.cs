using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;

public class PerPixelRT : MonoBehaviour {

    // acumulation material; handles temporal stability
    public Material accuMaterial;
    // materials for saving the G-Buffers of the previous frame
    public Material copyGBuffMat0, copyGBuffMat1, copyGBuffMat2, copyGBuffMatD;
    private RenderTexture prevGBuff0, prevGBuff1, prevGBuff2, prevGBuffD;

    // raytracing shader
    public RayTracingShader rayTracingShader;

    // textures for accumulation
    private RenderTexture accu1, accu2;

    public void CreateTargets(RenderTexture giTarget){
        Destroy();
        accu1 = new RenderTexture(giTarget);
        accu2 = new RenderTexture(giTarget);

        int width = giTarget.width;
        int height = giTarget.height;

        prevGBuff0 = new RenderTexture(width, height, 0, RenderTextureFormat.ARGB32, RenderTextureReadWrite.Default);
        prevGBuff0.enableRandomWrite = true;
        prevGBuff1 = new RenderTexture(prevGBuff0);
        prevGBuff2 = new RenderTexture(prevGBuff0);
        prevGBuffD = new RenderTexture(width, height, 0, RenderTextureFormat.RFloat, RenderTextureReadWrite.Default);

        prevGBuff1.enableRandomWrite = true;
        prevGBuff2.enableRandomWrite = true;
        prevGBuffD.enableRandomWrite = true;

        prevGBuff0.Create();
        prevGBuff1.Create();
        prevGBuff2.Create();
        prevGBuffD.Create();

    }
    
    public void Destroy(){
        if(accu1 != null) accu1.Release();
        if(accu2 != null) accu2.Release();
        accu1 = accu2 = null;
        if(prevGBuff0 != null) prevGBuff0.Release();
        if(prevGBuff1 != null) prevGBuff1.Release();
        if(prevGBuff2 != null) prevGBuff2.Release();
        if(prevGBuffD != null) prevGBuffD.Release();
        prevGBuff0 = prevGBuff1 = prevGBuff2 = prevGBuffD = null;
    }

    private void UpdatePixelGI(DXRCamera cam) {
        var shader = rayTracingShader;
        shader.SetAccelerationStructure("_RaytracingAccelerationStructure", cam.sceneRTAS);
        shader.SetInt("_FrameIndex", cam.frameIndex);
        shader.SetInt("_SPP", cam.samplesPerPixel);
        shader.SetInt("_RPS", cam.raysPerSample);
        shader.SetVector("_CameraPosition", transform.position);
        shader.SetVector("_CameraRotation", DXRCamera.QuatToVec(transform.rotation));
        shader.SetVector("_CameraOffset", cam.CalcCameraOffset());
        shader.SetTexture("_SkyBox", cam.skyBox);
        shader.SetTexture("_DxrTarget", cam.giTarget);
        shader.SetShaderPass("DxrPass");
        shader.Dispatch("PixelGI", cam.giTarget.width, cam.giTarget.height, 1, cam._camera);
    }

    private void AccumulatePixelGI(DXRCamera cam, Vector3 deltaPos) {
        var shader = accuMaterial;
        shader.SetVector("_DeltaCameraPosition", deltaPos);
        shader.SetTexture("_CurrentFrame", cam.giTarget);
        shader.SetTexture("_Accumulation", accu1);
        shader.SetInt("_FrameIndex", cam.frameIndex);
        shader.SetTexture("prevGBuff0", prevGBuff0);
        shader.SetTexture("prevGBuff1", prevGBuff1);
        shader.SetTexture("prevGBuff2", prevGBuff2);
        shader.SetTexture("prevGBuffD", prevGBuffD);
        Graphics.Blit(cam.giTarget, accu2, shader);
    }

    private void PreservePrevGBuffers(){
        Graphics.Blit(null, prevGBuff0, copyGBuffMat0);
        Graphics.Blit(null, prevGBuff1, copyGBuffMat1);
        Graphics.Blit(null, prevGBuff2, copyGBuffMat2);
        Graphics.Blit(null, prevGBuffD, copyGBuffMatD);
    }

    public void RenderImage(DXRCamera cam, RenderTexture destination){

        // start path tracer
        UpdatePixelGI(cam);

        // accumulate current raytracing result
        Vector3 pos = transform.position;
        Vector3 deltaPos = pos - cam.prevCameraPosition;
        AccumulatePixelGI(cam, deltaPos);

        // display result on screen
        Material displayMaterial = cam.displayMaterial;
        displayMaterial.SetVector("_Duv", new Vector2(1f/(cam._camera.pixelWidth-1f), 1f/(cam._camera.pixelHeight-1f)));
        displayMaterial.SetFloat("_DivideByAlpha", 0f);
        displayMaterial.SetTexture("_SkyBox", cam.skyBox);
        displayMaterial.SetTexture("_Accumulation", accu2);
        displayMaterial.SetFloat("_Far", cam._camera.farClipPlane);
        displayMaterial.SetFloat("_ShowIllumination", cam.showIllumination ? 1f : 0f);
        displayMaterial.SetVector("_CameraPosition", pos);
        displayMaterial.SetVector("_CameraRotation", DXRCamera.QuatToVec(transform.rotation));
        displayMaterial.SetFloat("_Derivatives", 0f);
        float zFactor2 = 1.0f / Mathf.Tan(cam._camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
        displayMaterial.SetVector("_CameraScale", new Vector2((zFactor2 * cam._camera.pixelWidth) / cam._camera.pixelHeight, zFactor2));
        Graphics.Blit(accu2, destination, displayMaterial);

        PreservePrevGBuffers();

        // switch accumulation textures
        var temp = accu1;
        accu1 = accu2;
        accu2 = temp;

    }
}
