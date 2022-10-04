using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class Flicker : MonoBehaviour {

    private MeshRenderer _renderer;
    public int period, phase;
    
    void Start() {
        _renderer = GetComponent<MeshRenderer>();
    }

    void Update() {
        phase++;
        if(_renderer != null){
            _renderer.enabled = (phase % period) >= period / 2;
        }
    }
}
