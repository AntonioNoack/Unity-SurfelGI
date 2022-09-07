using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;

public class ComputeDebugger : EditorWindow {
    private HashSet<string> stages = new HashSet<string>();
    public string selectedStage;
    private string[,] data;
    public void GiveComputeBuffer<T>(string name, ComputeBuffer data, System.Func<T, int, string> serializer) {
        stages.Add(name);
        if(selectedStage == name && data.count > 0){
            // get data for drawing
            var tmp = new T[data.count];
            data.GetData(tmp);
            T sample = tmp[0];
            // find how many elements there are
            int propertyCount = 0;
            while(true) {
                if(serializer(sample, propertyCount) == null) break; // end of struct
                propertyCount++;
            }
            this.data = new string[data.count, propertyCount];
            for(int i=0;i<data.count;i++){
                sample = tmp[i];
                for(int j=0;j<propertyCount;j++){
                    this.data[i, j] = serializer(sample, j);
                }
            }
        }
    }
    
    int selected = 0;
    void OnGUI () {
        // enum selector for stage selection
        if(stages.Count > 0){
            string[] options = new string[stages.Count];
            stages.CopyTo(options);
            selected = EditorGUILayout.Popup("Label", selected, options);
            selectedStage = options[selected];
        }
        GUILayout.Label("Stage", EditorStyles.boldLabel);
        if(data != null){
            GUILayout.Label("Data, "+data.Length+" elements", EditorStyles.boldLabel);
            // todo display table
            
        } else {
            GUILayout.Label("Please select a stage", EditorStyles.boldLabel);
        }
    }
}
