using System; // NaN
using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Windows; // saving/loading binary files

// todo use this
public class RMSE : MonoBehaviour {

    public ComputeShader shader;
    private ComputeBuffer tmp;
    private float[] data;


    // todo also encode variance?

    public static void SaveImage(string path, Texture2D tex) {
        // While EXR would be great to not loose any information, Unity cannot load it at runtime.
        // byte[] data = ImageConversion.EncodeToEXR(tex, Texture2D.EXRFlags.OutputAsFloat | Texture2D.EXRFlags.CompressZIP);
        byte[] data = ImageConversion.EncodeToPNG(tex);
        File.WriteAllBytes(path, data);
    }

    public static Texture2D LoadImage(string path) {
        if(!File.Exists(path)) {
            Debug.Log("Path \""+path+"\" doesn't exist!");
            return null;
        }
        byte[] data = File.ReadAllBytes(path);
        Texture2D dst = new Texture2D(1, 1); // contents will be replaced
        bool success = ImageConversion.LoadImage(dst, data, false);
        if(!success) Debug.Log("Failed to decode image from \""+path+"\"");
        return success ? dst : null;
    }

    // https://stackoverflow.com/questions/44264468/convert-rendertexture-to-texture2d
    public static Texture2D ToTexture2D(RenderTexture src) {
        Texture2D dst = new Texture2D(src.width, src.height, TextureFormat.RGBAFloat, false);
        // ReadPixels looks at the active RenderTexture.
        var old = RenderTexture.active;
        RenderTexture.active = src;
        dst.ReadPixels(new Rect(0, 0, src.width, src.height), 0, 0);
        dst.Apply();
        RenderTexture.active = old;
        return dst;
    }

    public static RenderTexture ToRenderTexture(Texture2D src, RenderTexture dst = null) {
        if(dst == null) {
            // format could be better matched to src;
            // when we do that, we might have to check the SRGB flag is correctly set
            dst = new RenderTexture(src.width, src.height, 0, RenderTextureFormat.ARGBFloat);
            dst.enableRandomWrite = true;
        }
        Graphics.Blit(src, dst);
        return dst;
    }

    public float Compute(RenderTexture a, RenderTexture b){
        int sx = (a.width+31)>>5;
        int sy = (a.height+31)>>5;
        int size = sx*sy;
        if(tmp == null || tmp.count != size){
            // create new buffer
            if(tmp != null) tmp.Release();
            int stride = 4;// sizeof(float)
            tmp = new ComputeBuffer(size, stride);
            data = new float[size];
        }
        int kernel = shader.FindKernel("RMSEKernel");
        shader.SetTexture(kernel, "Src1", a);
        shader.SetTexture(kernel, "Src2", b);
        shader.SetBuffer(kernel, "Dst", tmp);
        shader.Dispatch(kernel, sx, sy, 1);
        tmp.GetData(data);
        double sum = 0;
        for(int i=0;i<size;i++){
            sum += data[i];
        }
        double avg = sum / (a.width * a.height);
        return (float) Math.Sqrt(avg);
    }
    
    public void Destroy(){
        if(tmp != null) tmp.Release();
        tmp = null;
        data = null;
    }
}
