using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class ShaderMapping : MonoBehaviour {

    // todo what is the most generic way to replace shaders?

    [System.Serializable]
    public struct Mapping {
        public Shader oldShader, newShader;
        public PropertyMapping[] properties;
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
            Material material = renderer.material;
            if(material != null){
                Shader shader = material.shader;
                if(mappings2.ContainsKey(shader)){
                    Mapping mapping = mappings2[shader];
                    PropertyMapping[] properties = mapping.properties;
                    if(properties != null){
                        foreach(var property in properties){
                            if(material.HasProperty(property.oldName)){
                                
                            }
                        }
                    }
                    // todo transfer all properties
                    material.shader = mapping.newShader;
                }
            }
        }
    }

    void Update() {
        
    }
}
