

float dist = dot(localPosition, localPosition);
                
float deltaSpecular = abs(specular - i.surfelData.x);
float deltaSmoothness = abs(smoothness - i.surfelData.y);

float weight = // 0.001 + 0.999 * 
    saturate(1.0/(1.0+20.0*dist)-0.1667) *
	saturate(dot(i.surfelNormal, normal)) *
	saturate(1.0-20.0*deltaSmoothness) *
	saturate(1.0-20.0*deltaSpecular);
    // don't forget to adjust it in shader without gradients as well!!