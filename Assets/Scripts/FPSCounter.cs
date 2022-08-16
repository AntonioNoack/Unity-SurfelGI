using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using TMPro;

public class FPSCounter : MonoBehaviour {

    private float smoothFrameTime = 0f;

    [Range(0f, 10f)]
    public float smoothing = 3f;
    
    void Update() {
        float frameTime = Time.deltaTime;
        smoothFrameTime = Mathf.Lerp(smoothFrameTime, frameTime, Mathf.Exp(-smoothing));
    }

    private void OnGUI() {
        int fps = Mathf.RoundToInt(10f / smoothFrameTime);
        if(SystemInfo.supportsRayTracing){
            GUILayout.Label((fps/10) + "." + (fps%10) + " fps");
        } else {
            GUILayout.Label("RayTracing is not supported, Surfel GI won't work!!!");
        }
    }

}
