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

    public void UpdatePixelGI(DXRCamera cam) {
        var shader = cam.InitPathTracing(false);
        shader.SetTexture("_ColorTarget", cam.emissiveTarget);
        shader.SetTexture("_ColorDxTarget", cam.emissiveDxTarget);
        shader.SetTexture("_ColorDyTarget", cam.emissiveDyTarget);
        shader.Dispatch("PixelPathTracing", cam.emissiveTarget.width, cam.emissiveTarget.height, 1, cam._camera);
    }

    public RenderTexture AccumulatePixelGI(DXRCamera cam) {
        Vector3 deltaPos = transform.position - cam.prevCameraPosition;
        var shader = accuMaterial;
        shader.SetVector("_DeltaCameraPosition", deltaPos);
        shader.SetTexture("_CurrentFrame", cam.emissiveTarget);
        shader.SetTexture("_Accumulation", accu1);
        shader.SetInt("_FrameIndex", cam.frameIndex);
        shader.SetTexture("prevGBuff0", prevGBuff0);
        shader.SetTexture("prevGBuff1", prevGBuff1);
        shader.SetTexture("prevGBuff2", prevGBuff2);
        shader.SetTexture("prevGBuffD", prevGBuffD);
        shader.SetFloat("_Discard", cam.resetPixelGI ? 1f : 0f);
        Graphics.Blit(null, accu2, shader);
        cam.resetPixelGI = false;
        return accu2;
    }

    public void PreservePrevGBuffers(){
        Graphics.Blit(null, prevGBuff0, copyGBuffMat0);
        Graphics.Blit(null, prevGBuff1, copyGBuffMat1);
        Graphics.Blit(null, prevGBuff2, copyGBuffMat2);
        Graphics.Blit(null, prevGBuffD, copyGBuffMatD);
    }

    public void SwapAccumulationTextures(){
        var temp = accu1;
        accu1 = accu2;
        accu2 = temp;
    }

}
