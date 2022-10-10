#ifndef MATERIAL_CGINC
#define MATERIAL_CGINC

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/conductor.cpp
float3 Conductor_eval(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure) {
	// perfectly smooth conductor
	if(measure != EDiscrete || 
		Frame_cosTheta(rec.wi) <= 0.0 || 
		Frame_cosTheta(rec.wo) <= 0.0 ||
		abs(dot(reflect(rec.wi), rec.wo)-1.0) > DeltaEpsilon
	) return 0;
	float eta = 1.5;
	float k = 0.0;
	return bsdf.color * fresnelConductorExact(Frame_cosTheta(rec.wi), eta, k);
}

float Conductor_pdf(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure) {
	if(measure != EDiscrete || 
		Frame_cosTheta(rec.wi) <= 0.0 || 
		Frame_cosTheta(rec.wo) <= 0.0 ||
		abs(dot(reflect(rec.wi), rec.wo)-1.0) > DeltaEpsilon
	) return 0;
	return abs(dot(reflect(rec.wi), rec.wo)-1.0) < 0.01 ? 1.0 : 0.0; // set pdf to 0 if dir != reflectDir
}

float3 Conductor_sample(BSDF bsdf, inout BSDFSamplingRecord rec, out float pdf, float2 seed) {
	if(Frame_cosTheta(rec.wi) <= 0.0) return 0;
	rec.sampledType = EDeltaReflection;
	rec.wo = reflect(rec.wi);
	pdf = 1.0;
	float eta = 1.5;
	float k = 0.0;
	return bsdf.color * fresnelConductorExact(Frame_cosTheta(rec.wi), eta, k);
}

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/roughconductor.cpp
float3 RoughConductor_eval(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure) {
	if(measure != ESolidAngle || 
		Frame_cosTheta(rec.wi) <= 0 || 
		Frame_cosTheta(rec.wo) <= 0) return 0;
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

float3 RoughConductor_pdf(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure) {
	if(measure != ESolidAngle || 
		Frame_cosTheta(rec.wi) <= 0 || 
		Frame_cosTheta(rec.wo) <= 0) return 0;
	MicrofacetType type = Beckmann;
	float eta = 1.5;
	float k = 0.0;
	float3 wi = rec.wi, wo = rec.wo;
	float alphaU = bsdf.roughness, alphaV = alphaU;
	float exponentU = 0, exponentV = exponentU;
	float3 H = normalize(wo + wi);		
	return distrEval(type, alphaU, alphaV, exponentU, exponentV, H) * distrSmithG1(type, alphaU, alphaV, wi, H) / (4.0 * Frame_cosTheta(wi));
}

float3 RoughConductor_sample(BSDF bsdf, inout BSDFSamplingRecord rec, out float pdf, float2 seed) {
	if(Frame_cosTheta(rec.wi) <= 0) return 0;
	float pdf0;
	float eta = 1.5;
	float k = 0.0;
	MicrofacetType type = Beckmann;
	float3 wi = rec.wi;
	float alphaU = bsdf.roughness, alphaV = alphaU;
	float exponentU = 0, exponentV = exponentU;
	float3 m = distrSample(type, alphaU, alphaV, exponentU, exponentV, wi, seed, pdf0);
	rec.wo = -reflect(wi, m);// the definition in mitsuba is the negative of the HLSL definition
	rec.sampledType = EGlossyReflection;
	float weight = distrSmithG1(type, alphaU, alphaV, reflect(wi), m);
	if(weight > 0) {
		pdf = pdf0 / (4.0 * dot(rec.wo, m));
		return bsdf.color * (pdf0 * fresnelConductorExact(dot(wi, m), eta, k));
	} else {
		pdf = 0;
		return 0;
	}
}

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/diffuse.cpp
float3 Diffuse_eval(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure) {
	if(measure != ESolidAngle || 
		Frame_cosTheta(rec.wi) <= 0 || 
		Frame_cosTheta(rec.wo) <= 0) return 0;
	return bsdf.color * INV_PI * Frame_cosTheta(rec.wo);
}

float Diffuse_pdf(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure) {
	if(measure != ESolidAngle || 
		Frame_cosTheta(rec.wi) <= 0 || 
		Frame_cosTheta(rec.wo) <= 0) return 0;
	return squareToCosineHemispherePdf(rec.wo);
}

float3 Diffuse_sample(BSDF bsdf, inout BSDFSamplingRecord rec, out float pdf, float2 seed) {
	if(Frame_cosTheta(rec.wi) <= 0) return 0;
	rec.sampledType = EDiffuseReflection;
	rec.wo = squareToCosineHemisphere(seed);
	pdf = squareToCosineHemispherePdf(rec.wo);
	return bsdf.color;
}

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/roughdiffuse.cpp
float3 RoughDiffuse_eval(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure) {
	if(measure != ESolidAngle || 
		Frame_cosTheta(rec.wi) <= 0 || 
		Frame_cosTheta(rec.wo) <= 0) return 0;
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

float RoughDiffuse_pdf(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure) {
	if(measure != ESolidAngle || 
		Frame_cosTheta(rec.wi) <= 0 || 
		Frame_cosTheta(rec.wo) <= 0) return 0;
	return squareToCosineHemispherePdf(rec.wo);
}

float3 RoughDiffuse_sample(BSDF bsdf, inout BSDFSamplingRecord rec, out float pdf, float2 seed) {
	if(Frame_cosTheta(rec.wi) <= 0) return 0;
	rec.wo = squareToCosineHemisphere(seed);
	rec.sampledType = EGlossyReflection;
	return RoughDiffuse_eval(bsdf, rec, ESolidAngle) / squareToCosineHemispherePdf(rec.wo);
}

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/dielectric.cpp
float3 evalDielectric(float3 wi, float3 wo, float3 color, float eta){// returns Color * pdf
	float cosThetaT;
	float F = fresnelDielectricExt(Frame_cosTheta(wi), cosThetaT, eta);
	if(Frame_cosTheta(wi) * Frame_cosTheta(wo) >= 0) {
		if(abs(dot(reflect(wi), wo)-1.0) > DeltaEpsilon) return 0; // if not close enough to perfect reflection, return 0
		return color * F;
	} else {
		if(abs(dot(refract(wi, cosThetaT), wo)-1.0) > DeltaEpsilon) return 0; // if not close enough to perfect refraction, return 0
		float factor = cosThetaT < 0.0 ? 1.0/eta : eta;
		return color * (factor * factor * (1.0 - F));
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
float3 RoughDielectric_eval(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure) {
	if(measure != ESolidAngle || Frame_cosTheta(rec.wi) == 0) return 0;
	MicrofacetType type = Beckmann;
	float alphaU = bsdf.roughness, alphaV = alphaU;
	float expU = 0, expV = 0;
	bool reflect1 = Frame_cosTheta(rec.wi) * Frame_cosTheta(rec.wo) > 0;
	float3 H;
	if(reflect1){
		H = normalize(rec.wi+rec.wo);
	} else {
		float eta = Frame_cosTheta(rec.wi) > 0 ? bsdf.eta : 1.0 / bsdf.eta;
		H = normalize(rec.wi+rec.wo*eta);
	}
	H *= sign(Frame_cosTheta(H));
	float D = distrEval(type, alphaU, alphaV, expU, expV, H);
	if(D == 0.0) return 0;
	float F = fresnelDielectricExt(dot(rec.wi, H), bsdf.eta);
	float G = distrG(type, alphaU, alphaV, rec.wi, rec.wo, H);
	if(reflect1){
		return bsdf.color * F * D * G / (4.0 * abs(Frame_cosTheta(rec.wi)));
	} else {
		float eta = Frame_cosTheta(rec.wi) > 0 ? bsdf.eta : 1.0 / bsdf.eta;
		float sqrtDenom = dot(rec.wi, H) + eta * dot(rec.wo, H);
		float value = (1.0 - F) * D * G * eta * eta * dot(rec.wi, H) * dot(rec.wo, H) / (Frame_cosTheta(rec.wi) * sqrtDenom * sqrtDenom);
		float factor = Frame_cosTheta(rec.wi) > 0 ? 1.0 / eta : eta;
		return bsdf.color * abs(value * factor * factor);
	}
}

float RoughDielectric_pdf(BSDF bsdf, BSDFSamplingRecord rec, EMeasure measure) {
	if(measure != ESolidAngle || Frame_cosTheta(rec.wi) == 0) return 0;
	MicrofacetType type = Beckmann;
	float alphaU = bsdf.roughness, alphaV = alphaU;
	float expU = 0, expV = 0;
	bool reflect1 = Frame_cosTheta(rec.wi) * Frame_cosTheta(rec.wo) > 0;
	float3 H;
	float dwh_dwo;
	if(reflect1){
		H = normalize(rec.wi+rec.wo);
		dwh_dwo = 0.25 / dot(rec.wo, H);
	} else {
		float eta = Frame_cosTheta(rec.wi) > 0 ? bsdf.eta : 1.0 / bsdf.eta;
		H = normalize(rec.wi+rec.wo*eta);
		float sqrtDenom = dot(rec.wi, H) + eta * dot(rec.wo, H);
		dwh_dwo = (eta*eta*dot(rec.wo, H)) / (sqrtDenom * sqrtDenom);
	}
	H *= sign(Frame_cosTheta(H));
	float prob = pdfVisible(type, alphaU, alphaV, expU, expV, sign(Frame_cosTheta(rec.wi)) * rec.wi, H);
	float F = fresnelDielectricExt(dot(rec.wi, H), bsdf.eta);
	prob *= reflect1 ? F : 1.0 - F;
	return abs(prob * dwh_dwo);
}

float3 RoughDielectric_sample(BSDF bsdf, inout BSDFSamplingRecord rec, out float pdf, float2 seed) {
	float microfacetPdf;
	MicrofacetType type = Beckmann;
	float alphaU = bsdf.roughness, alphaV = alphaU;
	float expU = 0, expV = 0;
	float3 m = distrSample(type, alphaU, alphaV, expU, expV, sign(Frame_cosTheta(rec.wi)) * rec.wi, seed, microfacetPdf);
	if(microfacetPdf == 0) return 0;
	float temporaryPdf = microfacetPdf;
	float cosThetaT;
	float F = fresnelDielectricExt(dot(rec.wi, m), cosThetaT, bsdf.eta);
	float3 weight = float3(1,1,1);
	bool sampleReflection = true;
	float dwh_dwo;
	if(nextRand(rec.its.randomSeed) > F){
		sampleReflection = false;
		temporaryPdf *= 1.0-F;
		rec.wo = -reflect(rec.wi, m);// mirrored because def difference
		rec.eta = 1;
		rec.sampledType = EGlossyReflection;
		if(Frame_cosTheta(rec.wi) * Frame_cosTheta(rec.wo) <= 0)
			return 0;
		weight *= bsdf.color;
		dwh_dwo = 0.25 / dot(rec.wo, m);
	} else {
		temporaryPdf *= F;
		if(cosThetaT == 0) return 0;
		rec.wo = refract(rec.wi, m, bsdf.eta, cosThetaT);
		rec.eta = cosThetaT < 0 ? bsdf.eta : 1.0 / bsdf.eta;
		rec.sampledType = EGlossyTransmission;
		if(Frame_cosTheta(rec.wi) * Frame_cosTheta(rec.wo) >= 0)
			return 0;
		float factor = cosThetaT < 0 ? 1.0 / bsdf.eta : bsdf.eta;
		weight *= bsdf.color * (factor * factor);
		float sqrtDenom = dot(rec.wi, m) + dot(rec.wo, m) * rec.eta;
		dwh_dwo = (rec.eta * rec.eta * dot(rec.wo, m)) / (sqrtDenom * sqrtDenom);
	}
	weight *= distrSmithG1(type, alphaU, alphaV, rec.wo, m);
	temporaryPdf *= abs(dwh_dwo);
	pdf = temporaryPdf;
	return weight;
}


#endif // MATERIAL_CGINC