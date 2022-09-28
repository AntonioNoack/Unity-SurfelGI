using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEditor;
using System;

// from https://gist.github.com/bartofzo/6ad28a05ba9fc82e10a64f0c121c5c24
// then adjusted to be truly just logarithmic
[AttributeUsage(AttributeTargets.Field | AttributeTargets.Property)]
public class LogarithmicRangeAttribute : PropertyAttribute {
    public double min;
    public double max;
    public LogarithmicRangeAttribute(double min, double max) {
        this.min = min;
        this.max = max;
    }
}
    
#if UNITY_EDITOR
[CustomPropertyDrawer(typeof(LogarithmicRangeAttribute))]
public class LogRangePropertyDrawer : PropertyDrawer {
    public override void OnGUI(Rect position, SerializedProperty property, GUIContent label) {
        LogarithmicRangeAttribute attribute = (LogarithmicRangeAttribute) this.attribute;

        EditorGUI.BeginProperty(position, label, property);
        position = EditorGUILayout.GetControlRect(false, EditorGUIUtility.singleLineHeight);
        // position = EditorGUI.PrefixLabel(position, GUIUtility.GetControlID(FocusType.Passive), label);

        double logMax = Math.Log10(attribute.max);
        double logMin = Math.Log10(attribute.min);

        double realValue = Math.Max(Math.Min(property.doubleValue, attribute.max), attribute.min);
        double value = Math.Log10(realValue);
        // without log10 number
        // value = GUI.HorizontalSlider(position, (float) value, (float) logMin, (float) logMax);
        // with log10 number
        value = EditorGUI.Slider(position, "Exposure", (float) value, (float) logMin, (float) logMax);
        property.doubleValue = Math.Pow(10.0, value);

        // with actual number, but hacky
        // double gradient = 1000 * realValue;// d/dx exp = exp; small pre-factors are great for mouse-usability; large prefactors are great for manual number input
        // double relative = (value - logMin) / (logMax - logMin);
        // property.doubleValue = EditorGUI.Slider(position, "Exposure", (float) realValue, (float) (realValue - gradient * relative), (float) (realValue + gradient * (1.0 - relative)));


        var defaultAlignment = GUI.skin.label.alignment;
        GUI.skin.label.alignment = TextAnchor.UpperRight;
        GUILayout.Label(((float) property.doubleValue).ToString().Replace(",", "."));
        GUI.skin.label.alignment = defaultAlignment;
           
        EditorGUI.EndProperty();
    }
}
#endif