using System.Collections;
using System.Collections.Generic;
using UnityEngine;

/**
 * Poisson Image Reconstruction
 */
public class PoissonReconstruction : MonoBehaviour {

    // allows you to enable/disable the component
    void Start(){

    }
    
    public int poissonBlurRadius = 25;
    public int numPoissonIterations = 10;
    public Shader blurShader;
    public Material poissonMaterial, addMaterial, normMaterial;

    private void blur(RenderTexture src, RenderTexture tmp, RenderTexture dst){
        blurX(src, tmp);
        blurY(tmp, dst);
    }

    private void kernel(RenderTexture src, RenderTexture dst, int dx, int dy, Material material) {
        if(material == null){
            Debug.LogWarning("Material for kernel is null!");
            return;
        } else if(src == null){
            Debug.LogWarning("src for kernel is null!");
            return;
        }
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
        if(a == null || b == null || c == null){
            Debug.LogError("Textures are null!!!");
            return;
        }
        shader.SetTexture("_MainTex", a);
        shader.SetTexture("_TexA", a);
        shader.SetTexture("_TexB", b);
        shader.SetTexture("_TexC", c);
        Graphics.Blit(null, dst, shader);
    }

    private RenderTexture blurred, bdx, bdy, res0, src1, dx1, dy1;
    private float[] unsignedBlurMask, signedBlurMask;
    private Material signedBlurMaterial, unsignedBlurMaterial;
    private float gaussianWeight(int i, float n, float sigma){ // gaussian bell curve with standard deviation <sigma> from -<n> to <n>
        float x = i / n;
        return Mathf.Exp(-x*x*sigma);
    }

    void OnDestroy(){
        Destroy();
    }

    private void Destroy(){
        if(src1 != null) src1.Release();
        if(dx1 != null) dx1.Release();
        if(dy1 != null) dy1.Release();
        if(bdx != null) bdx.Release();
        if(bdy != null) bdy.Release();
        if(res0 != null) res0.Release();
        if(blurred != null) blurred.Release();
    }

    private void Create(int w, int h){
        bdx = Create2(w,h);
        bdy = Create2(w,h);
        res0 = Create2(w,h);
        blurred = Create2(w,h);
        src1 = Create2(w,h);
        dx1 = Create2(w,h);
        dy1 = Create2(w,h);
    }

    private RenderTexture Create2(int w, int h){
        var bdx = new RenderTexture(w, h, 0, RenderTextureFormat.ARGBFloat, RenderTextureReadWrite.Default);
        bdx.enableRandomWrite = true;
        bdx.Create();
        return bdx;
    }

    public bool normalize = true;
    public RenderTexture poissonReconstruct(RenderTexture src, RenderTexture dx, RenderTexture dy) {

        if(bdx == null || bdx.width != src.width || bdx.height != src.height){
            Debug.Log("Recreating buffers");
            Destroy();
            Create(src.width, src.height);
        }

        if(normalize){
            Graphics.Blit(src, src1, normMaterial);
            Graphics.Blit(dx, dx1, normMaterial);
            Graphics.Blit(dy, dy1, normMaterial);
            src = src1;
            dx = dx1;
            dy = dy1;
        }

        if(signedBlurMaterial == null){
            if(blurShader == null){
                Debug.Log("Blur Shader is missing!");
                return src;
            }
            Debug.Log("Creating blur materials");
            signedBlurMaterial = new Material(blurShader);
            unsignedBlurMaterial = new Material(blurShader);
        }

        if(unsignedBlurMask == null || unsignedBlurMask.Length != poissonBlurRadius * 2 + 1){
            Debug.Log("Creating masks");
            // create blur masks
            float sigma = 2.5f;
            unsignedBlurMask = new float[poissonBlurRadius * 2 + 1];
            signedBlurMask = new float[poissonBlurRadius * 2 + 1];
            float weightSum = 0f;
            int n = Mathf.Max(poissonBlurRadius, 1);
            for(int i=1;i<=poissonBlurRadius;i++){
                weightSum += gaussianWeight(i, n, sigma);
            }
            weightSum = 2 * weightSum + gaussianWeight(0, n, sigma);
            float weightScale = 1f / weightSum;
            for(int i=0;i<=poissonBlurRadius;i++){
                float weight = weightScale * gaussianWeight(i, n, sigma);
                int j = poissonBlurRadius+i;
                int k = poissonBlurRadius-i;
                unsignedBlurMask[k] = +weight;
                unsignedBlurMask[j] = +weight;
                signedBlurMask[k] = -weight;
                signedBlurMask[j] = +weight;
            }
            signedBlurMask[poissonBlurRadius] = 0; // blur mask must be symmetric
            signedBlurMaterial.SetFloatArray("_Weights", signedBlurMask);
            unsignedBlurMaterial.SetFloatArray("_Weights", unsignedBlurMask);
            // Debug.Log(string.Join(";", signedBlurMask));
        }
        
        signedBlurMaterial.SetInt("_N", poissonBlurRadius);
        unsignedBlurMaterial.SetInt("_N", poissonBlurRadius);

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
