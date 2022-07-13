using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class Flicker : MonoBehaviour {

    private new MeshRenderer renderer;
    public int period, phase;
    
    void Start() {
        renderer = GetComponent<MeshRenderer>();
    }

    void Update() {
        phase++;
        if(renderer != null){
            renderer.enabled = (phase % period) >= period / 2;
        }
    }
}
