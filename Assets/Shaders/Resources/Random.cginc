#ifndef RANDOM_CGING
#define RANDOM_CGING

// compute random seed from one input
// http://reedbeta.com/blog/quick-and-easy-gpu-random-numbers-in-d3d11/
uint initRand(uint seed) {
	seed = (seed ^ 61) ^ (seed >> 16);
	seed *= 9;
	seed = seed ^ (seed >> 4);
	seed *= 0x27d4eb2d;
	seed = seed ^ (seed >> 15);
	return seed;
}

// compute random seed from two inputs
// https://github.com/nvpro-samples/optix_prime_baking/blob/master/random.h
uint initRand(uint seed1, uint seed2) {
	uint seed = 0;

	[unroll]
	for(uint i = 0; i < 16; i++) {
		seed += 0x9e3779b9;
		seed1 += ((seed2 << 4) + 0xa341316c) ^ (seed2 + seed) ^ ((seed2 >> 5) + 0xc8013ea4);
		seed2 += ((seed1 << 4) + 0xad90777d) ^ (seed1 + seed) ^ ((seed1 >> 5) + 0x7e95761e);
	}
	
	return seed1;
}

// next random number
// http://reedbeta.com/blog/quick-and-easy-gpu-random-numbers-in-d3d11/
float nextRand(inout uint seed) {
	seed = 1664525u * seed + 1013904223u;
	return float(seed & 0x00FFFFFF) / float(0x01000000);
}

int nextRandInt(inout uint seed) {
	seed = 1664525u * seed + 1013904223u;
	int data0 = seed & 0xffff;
	seed = 1664525u * seed + 1013904223u;
	int data1 = seed & 0xffff;
	return data0 | (data1 << 16);
}

float3 nextRandS3(inout uint seed0) {
	uint seed = seed0;
	float3 v = float3(nextRand(seed), nextRand(seed), nextRand(seed))*2-1;
	for(int i=0;i<10;i++){
		if(dot(v,v) <= 1.0) break;
		v = float3(nextRand(seed), nextRand(seed), nextRand(seed))*2-1;
	}
	seed0 = seed;
	return v;
}

#endif // RANDOM_CGING