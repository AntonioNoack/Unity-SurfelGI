using System;
using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class ShaderMapping : MonoBehaviour {

    // todo what is the most generic way to replace shaders?

    [System.Serializable]
    public struct Mapping {
        public Shader oldShader, newShader;
    };

    [System.Serializable]
    public struct PropertyMapping {
        public string oldName, newName;
    };

    public Mapping[] mappings;
    
    void Start() {
        if(mappings == null) return;
        var mappings2 = new Dictionary<Shader,Mapping>(mappings.Length * 2);
        for(int i=0,l=mappings.Length;i<l;i++){
            mappings2[mappings[i].oldShader] = mappings[i];
        }
        foreach(var renderer in FindObjectsOfType<MeshRenderer>()){
            // to do can we use shared materials?
            Material[] materials = renderer.sharedMaterials;
            for(int i=0,l=materials.Length;i<l;i++){
                Material material = materials[i];
                Shader shader = material.shader;
                if(mappings2.ContainsKey(shader)){
                /*Debug.Log("Material "+material+
                    " has texs "+String.Join(", ", material.GetTexturePropertyNames())+
                    " with ids "+String.Join(", ", material.GetTexturePropertyNameIDs()));*/
                    material.shader = mappings2[shader].newShader;
                }
            }
            renderer.sharedMaterials = materials;
        }
    }

    void Update() {
        
    }
}
