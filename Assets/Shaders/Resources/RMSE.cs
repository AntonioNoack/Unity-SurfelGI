using System; // NaN
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

// todo use this
public class RMSE : MonoBehaviour {

    public ComputeShader shader;
    private ComputeBuffer tmp;
    private float[] data;

    float Compute(RenderTexture a, RenderTexture b){
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
        int kernel = shader.FindKernel("RSMEKernel");
        if(kernel < 0) {
            Debug.LogWarning("Kernel was not found!");
            return Single.NaN;
        }
        shader.SetTexture(kernel, "_Src1", a);
        shader.SetTexture(kernel, "_Src2", b);
        shader.SetBuffer(kernel, "_Dst", tmp);
        shader.Dispatch(kernel, sx, sy, 1);
        tmp.GetData(data);
        double sum = 0;
        for(int i=0;i<size;i++){
            sum += data[i];
        }
        double avg = sum / (a.width * a.height);
        return (float) Math.Sqrt(avg);
    }
    void Destroy(){
        if(tmp != null) tmp.Release();
        tmp = null;
        data = null;
    }
}
