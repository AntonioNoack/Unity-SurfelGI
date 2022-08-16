
   
    uint index = DispatchRaysIndex().x;
    uint randomSeed = initRand(index ^ 0xffff, _FrameIndex);
	float relativeIndex = (DispatchRaysIndex().x + nextRand(randomSeed)) / DispatchRaysDimensions().x;

	// ------------------------------------------------------------- //
	// binary search for correct triangle by size and emissive power //
	// ------------------------------------------------------------- //
	
	uint numTriangles, stride;
	g_Triangles.GetDimensions(numTriangles, stride);

	if(numTriangles == 0) return;

	int i0 = -1, i1 = numTriangles-1;
	while(i1 > i0){
		int im = (i0+i1) >> 1;
		if(im < 0) break;// first triangle
		float v = g_Triangles[im].accuIndex;
		if(relativeIndex < v){
			i1 = im;
		} else if(i0 < im){
			i0 = im;
		} else break;// we're done
	}

	int triIndex = i0 + 1;

	// load selected triangle
    Triangle tri = g_Triangles[triIndex];

	// choose random point on triangle
    float u = nextRand(randomSeed), v = nextRand(randomSeed);
    if(u + v > 1.0) {
        u = 1.0 - u;
        v = 1.0 - v;
    }
    float3 triA = float3(tri.ax,tri.ay,tri.az), triB = float3(tri.bx,tri.by,tri.bz), triC = float3(tri.cx,tri.cy,tri.cz);

	// get random vector
	float3 randomVector;int i=0;
	do {
		randomVector = float3(nextRand(randomSeed),nextRand(randomSeed),nextRand(randomSeed))*2-1;
	} while(i++ < 10 && dot(randomVector,randomVector) > 1.0);
    float3 rayDirection = normalize(randomVector);
    float3 rayOrigin = triA + (triB-triA) * u + (triC-triA) * v + rayDirection * 0.1;
