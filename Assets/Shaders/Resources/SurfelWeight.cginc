

float dist = dot(localPosition, localPosition);
                
float deltaSpecular = abs(specular - i.surfelData.x);
float deltaSmoothness = abs(smoothness - i.surfelData.y);

float weight = // 0.001 + 0.999 * 
    saturate(1.0/(1.0+20.0*dist)-0.1667) *
	saturate(dot(i.surfelNormal, normal)) *
	saturate(1.0-200.0*deltaSmoothness*max(smoothness,i.surfelData)) *
	saturate(1.0-20.0*deltaSpecular);
    // don't forget to adjust it in shader without gradients as well!!