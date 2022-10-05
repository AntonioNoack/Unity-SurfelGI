#ifndef MATERIAL_CGINC
#define MATERIAL_CGINC

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/conductor.cpp
float3 Conductor_eval(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure){
	// perfectly smooth conductor
	float eta = 1.5;
	float k = 0.0;
	return bsdf.color * fresnelConductorExact(Frame_cosTheta(rec.wi), eta, k);
}

float Conductor_pdf(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure){
	return abs(dot(reflect(rec.wi), rec.wo)-1.0) < 0.01 ? 1.0 : 0.0; // set pdf to 0 if dir != reflectDir
}

float3 Conductor_sample(BSDF bsdf, inout BSDFSamplingRecord rec, out float pdf, float2 seed){
	rec.sampledType = EDeltaReflection;
	rec.wo = reflect(rec.wi);
	pdf = 1.0;
	float eta = 1.5;
	float k = 0.0;
	return bsdf.color * fresnelConductorExact(Frame_cosTheta(rec.wi), eta, k);
}

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/roughconductor.cpp
float3 RoughConductor_eval(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure){
	MicrofacetType type = Beckmann;
	float eta = 1.5;
	float k = 0.0;
	float3 wi = rec.wi, wo = rec.wo;
	float alphaU = bsdf.roughness, alphaV = alphaU;
	float exponentU = 0, exponentV = exponentU;
	float3 H = normalize(wo + wi);		
	float D = distrEval(type, alphaU, alphaV, exponentU, exponentV, H);
	if(D == 0) return 0;
	// fresnel factor
	float3 F = fresnelConductorExact(dot(wi, H), eta, k) * bsdf.color;
	// shadow masking
	float G = distrG(type, alphaU, alphaV, wi, wo, H);
	// total amount of reflection
	float model = D * G / (4.0 * Frame_cosTheta(wi));
	return F * model;
}

float3 RoughConductor_pdf(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure){
	MicrofacetType type = Beckmann;
	float eta = 1.5;
	float k = 0.0;
	float3 wi = rec.wi, wo = rec.wo;
	float alphaU = bsdf.roughness, alphaV = alphaU;
	float exponentU = 0, exponentV = exponentU;
	float3 H = normalize(wo + wi);		
	return distrEval(type, alphaU, alphaV, exponentU, exponentV, H) * distrSmithG1(type, alphaU, alphaV, wi, H) / (4.0 * Frame_cosTheta(wi));
}

float3 RoughConductor_sample(BSDF bsdf, inout BSDFSamplingRecord rec, out float pdf, float2 seed){
	float pdf0;
	float eta = 1.5;
	float k = 0.0;
	MicrofacetType type = Beckmann;
	float3 wi = rec.wi, wo = rec.wo;
	float alphaU = bsdf.roughness, alphaV = alphaU;
	float exponentU = 0, exponentV = exponentU;
	float3 m = distrSample(type, alphaU, alphaV, exponentU, exponentV, wi, seed, pdf0);
	rec.wo = reflect(wi, m);
	rec.sampledType = EGlossyReflection;
	float weight = distrSmithG1(type, alphaU, alphaV, reflect(wi), m);
	if(weight > 0) {
		pdf = pdf0 / (4.0 * dot(wo, m));
		return bsdf.color * (pdf0 * fresnelConductorExact(dot(wi, m), eta, k));
	} else {
		pdf = 0;
		return 0;
	}
}

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/diffuse.cpp
float3 Diffuse_eval(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure){
	return bsdf.color * INV_PI * Frame_cosTheta(rec.wo);
}

float Diffuse_pdf(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure){
	return squareToCosineHemispherePdf(rec.wo);
}

float3 Diffuse_sample(BSDF bsdf, inout BSDFSamplingRecord rec, out float pdf, float2 seed){
	rec.sampledType = EDiffuseReflection;
	rec.wo = squareToCosineHemisphere(seed);
	pdf = squareToCosineHemispherePdf(rec.wo);
	return bsdf.color;
}

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/roughdiffuse.cpp
float3 RoughDiffuse_eval(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure){
	if(measure != ESolidAngle) return 0;
	float conversionFactor = INV_SQRT2;
	float sigma = bsdf.roughness * conversionFactor;
	float sigma2 = sigma*sigma;
	float sinThetaI = Frame_sinTheta(rec.wi);
	float sinThetaO = Frame_sinTheta(rec.wo);

	Float cosPhiDiff = 0;
	if (sinThetaI > Epsilon && sinThetaO > Epsilon) {
		/* Compute cos(phiO-phiI) using the half-angle formulae */
		Float sinPhiI = Frame_sinPhi(rec.wi),
			  cosPhiI = Frame_cosPhi(rec.wi),
			  sinPhiO = Frame_sinPhi(rec.wo),
			  cosPhiO = Frame_cosPhi(rec.wo);
		cosPhiDiff = cosPhiI * cosPhiO + sinPhiI * sinPhiO;
	}

	float A = 1.0f - 0.5f * sigma2 / (sigma2 + 0.33f);
	float B = 0.45f * sigma2 / (sigma2 + 0.09f);
	float sinAlpha, tanBeta;

	if (Frame_cosTheta(rec.wi) > Frame_cosTheta(rec.wo)) {
		sinAlpha = sinThetaO;
		tanBeta = sinThetaI / Frame_cosTheta(rec.wi);
	} else {
		sinAlpha = sinThetaI;
		tanBeta = sinThetaO / Frame_cosTheta(rec.wo);
	}

	return bsdf.color * (INV_PI * Frame_cosTheta(rec.wo) * (A + B * max(cosPhiDiff, 0.0) * sinAlpha * tanBeta));
}

float RoughDiffuse_pdf(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure){
	if(measure != ESolidAngle) return 0;
	return squareToCosineHemispherePdf(rec.wo);
}

float3 RoughDiffuse_sample(BSDF bsdf, inout BSDFSamplingRecord rec, out float pdf, float2 seed){
	rec.wo = squareToCosineHemisphere(seed);
	rec.sampledType = EGlossyReflection;
	return RoughDiffuse_eval(bsdf, rec, ESolidAngle) / squareToCosineHemispherePdf(rec.wo);
}

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/dielectric.cpp



float3 evalDielectric(float3 wi, float3 wo, float3 color, float eta){// returns Color * pdf
	float cosThetaT;
	float F = fresnelDielectricExt(Frame_cosTheta(wi), cosThetaT, eta);
	if(Frame_cosTheta(wi) * Frame_cosTheta(wo) >= 0){
		if(abs(dot(reflect(wi), wo)-1.0) > DeltaEpsilon) return 0; // if not close enough to perfect reflection, return 0
		return color * F;
	} else {
		if(abs(dot(refract(wi, cosThetaT), wo)-1.0) > DeltaEpsilon) return 0; // if not close enough to perfect refraction, return 0
		float factor = cosThetaT < 0.0 ? 1.0/eta : eta;
		return color * factor * factor * (1.0 - F);
	}
}

float3 Dielectric_eval(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure){
	float cosThetaT;
	float eta = bsdf.eta;
	float3 wi = rec.wi, wo = rec.wo;
	float F = fresnelDielectricExt(Frame_cosTheta(wi), cosThetaT, eta);
	if(Frame_cosTheta(wi) * Frame_cosTheta(wo) >= 0){
		if(abs(dot(reflect(wi), wo)-1.0) > DeltaEpsilon) return 0;// not close enough to ideal reflection
		return F * bsdf.color;
	} else {
		if(abs(dot(refract(wi, cosThetaT), wo)-1.0) > DeltaEpsilon) return 0;// not close enough to ideal refraction
		float factor = cosThetaT < 0 ? 1.0 / eta : eta;
		return bsdf.color * (factor * factor) * (1.0 - F);
	}
}

float Dielectric_pdf(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure){
	float cosThetaT;
	float3 wi = rec.wi, wo = rec.wo;
	float F = fresnelDielectricExt(Frame_cosTheta(wi), cosThetaT, bsdf.eta);
	if(Frame_cosTheta(wi) * Frame_cosTheta(wo) >= 0){
		if(abs(dot(reflect(wi), wo)-1.0) > DeltaEpsilon) return 0;// not close enough to ideal reflection
		return F;
	} else {
		if(abs(dot(refract(wi, cosThetaT), wo)-1.0) > DeltaEpsilon) return 0;// not close enough to ideal refraction
		return 1.0-F;
	}
}

float3 Dielectric_sample(inout BSDF bsdf, inout BSDFSamplingRecord rec, out float pdf, float2 seed){
	float cosThetaT;
	float3 wi = rec.wi;
	float eta = bsdf.eta;
	float F = fresnelDielectricExt(Frame_cosTheta(wi), cosThetaT, eta);
	if(seed.x <= F){
		rec.sampledType = EDeltaReflection;
		rec.wo = reflect(wi);
		pdf = F;
		return evalDielectric(wi, rec.wo, bsdf.color, eta);
	} else {
		rec.sampledType = EDeltaTransmission;
		rec.wo = refract(wi, eta);
		rec.eta = cosThetaT < 0 ? eta : 1.0 / eta;
		float factor = cosThetaT < 0 ? 1.0 / eta : eta;// ERadiance = true
		pdf = 1.0-F;
		return bsdf.color * (factor * factor);
	}
}

// todo implement and unlock in glass shader
float3 RoughDielectric_eval(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure){
	return 0;
}

float RoughDielectric_pdf(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure){
	return 0;
}

float3 RoughDielectric_sample(BSDF bsdf, inout BSDFSamplingRecord rec, out float pdf, float2 seed){
	return 0;
}


#endif // MATERIAL_CGINC