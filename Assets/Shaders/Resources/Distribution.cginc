#ifndef DISTR_CGINC
#define DISTR_CGINC

#define Float float
#define Spectrum float3
#define Vector float3
#define Normal float3
#define Point2 float2
#define Vector2 float2
#define M_PI 3.141592653589793
#define INV_TWOPI 0.15915494309189535
#define RCPOVERFLOW 2.93873587705571876e-39
#define SQRT_PI_INV 0.5641895835477563
#define Epsilon 1e-4

#define Frame float4

float Frame_cosTheta(const float3 v) {
    return v.z;
}

float Frame_n(const Frame f){
	return f[2]; // z component; column
}

float Frame_sinTheta2(const float3 v) {// sin(theta)²
	float c = Frame_cosTheta(v);
    return 1.0-c*c;
}

float Frame_cosTheta2(const float3 v) {
	float c = Frame_cosTheta(v);
	return c*c;
}

float Frame_sinTheta(const float3 v) {
    return sqrt(max(0, Frame_sinTheta2(v)));
}

float Frame_tanTheta(const float3 v) {
    return Frame_sinTheta(v)/Frame_cosTheta(v);
}

float hypot2(float a, float b){
	if(abs(a) > abs(b)){
		float r = b/a;
		return abs(a) * sqrt(1.0 + r*r);
	} else if(b != 0.0){
		float r = a/b;
		return abs(b) * sqrt(1.0 + r*r);
	} else return 0.0;
}

void sincos(float a, out float sin1, out float cos1){
	sin1 = sin(a);
	cos1 = cos(a);
}

float safe_sqrt(float a){
	return sqrt(max(a, 0.0));
}

Float erfinv(Float x) {
	// Based on "Approximating the erfinv function" by Mark Giles
	Float w = -log((1.0 - x)*(1.0 + x));
	Float p;
	if (w < 5.0) {
		w = w - 2.5;
		p =  2.81022636e-08;
		p =  3.43273939e-07 + p*w;
		p = -3.52338770e-06 + p*w;
		p = -4.39150654e-06 + p*w;
		p =  0.00021858087 + p*w;
		p = -0.00125372503 + p*w;
		p = -0.00417768164 + p*w;
		p =  0.246640727 + p*w;
		p =  1.50140941 + p*w;
	} else {
		w = sqrt(w) - 3.0;
		p = -0.000200214257;
		p =  0.000100950558 + p*w;
		p =  0.00134934322 + p*w;
		p = -0.00367342844 + p*w;
		p =  0.00573950773 + p*w;
		p = -0.00762246130 + p*w;
		p =  0.00943887047 + p*w;
		p =  1.00167406 + p*w;
		p =  2.83297682 + p*w;
	}
	return p*x;
}

Float erf(Float x) {
	Float a1 =  0.254829592;
	Float a2 = -0.284496736;
	Float a3 =  1.421413741;
	Float a4 = -1.453152027;
	Float a5 =  1.061405429;
	Float p  =  0.3275911;

	// Save the sign of x
	Float sign1 = sign(x);
	x = abs(x);

	// A&S formula 7.1.26
	Float t = 1.0 / (1.0 + p*x);
	Float y = 1.0 - (((((a5*t + a4)*t) + a3)*t + a2)*t + a1)*t*exp(-x*x);

	return sign1*y;
}

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/bsdfs/microfacet.h

enum MicrofacetType: int {
	Beckmann = 0, // Beckmann distribution derived from Gaussian random surfaces
	GGX = 1, // GGX: Long-tailed distribution for very rough surfaces (aka. Trowbridge-Reitz distr.)
	Phong = 2, // Phong distribution (with the anisotropic extension by Ashikhmin and Shirley)
};

// Compute the interpolated roughness for the Phong model
Float interpolatePhongExponent(bool isotropic, float m_exponentU, float m_exponentV, const Vector v) {
	const Float sinTheta2 = Frame_sinTheta2(v);

	if (isotropic || sinTheta2 <= RCPOVERFLOW)
		return m_exponentU;

	Float invSinTheta2 = 1 / sinTheta2;
	Float cosPhi2 = v.x * v.x * invSinTheta2;
	Float sinPhi2 = v.y * v.y * invSinTheta2;

	return m_exponentU * cosPhi2 + m_exponentV * sinPhi2;
}

// Compute the effective roughness projected on direction \c v
Float projectRoughness(float m_alphaU, float m_alphaV, const Vector v) {
	Float invSinTheta2 = 1.0 / Frame_sinTheta2(v);

	if (m_alphaU == m_alphaV || invSinTheta2 <= 0)
		return m_alphaU;

	Float cosPhi2 = v.x * v.x * invSinTheta2;
	Float sinPhi2 = v.y * v.y * invSinTheta2;

	return sqrt(cosPhi2 * m_alphaU * m_alphaU + sinPhi2 * m_alphaV * m_alphaV);
}

Float distrEval(
	MicrofacetType m_type,
	float m_alphaU, float m_alphaV, 
	float m_exponentU, float m_exponentV,
	const float3 m ) {
	if (Frame_cosTheta(m) <= 0)
		return 0.0;

	Float cosTheta2 = Frame_cosTheta2(m);
	Float beckmannExponent = ((m.x*m.x) / (m_alphaU * m_alphaU) + (m.y*m.y) / (m_alphaV * m_alphaV)) / cosTheta2;

	Float result;
	switch (m_type) {
		case Beckmann: {
			/* Beckmann distribution function for Gaussian random surfaces - [Walter 2005] evaluation */
			result = exp(-beckmannExponent) / (M_PI * m_alphaU * m_alphaV * cosTheta2 * cosTheta2);
			break;
		}
		case GGX: {
			/* GGX / Trowbridge-Reitz distribution function for rough surfaces */
			Float root = (1.0 + beckmannExponent) * cosTheta2;
			result = 1.0 / (M_PI * m_alphaU * m_alphaV * root * root);
			break;
		}
		default: { // Phong
			/* Isotropic case: Phong distribution. Anisotropic case: Ashikhmin-Shirley distribution */
			Float exponent = interpolatePhongExponent(m_alphaU == m_alphaV, m_exponentU, m_exponentV, m);
			result = sqrt((m_exponentU + 2.0) * (m_exponentV + 2.0)) * INV_TWOPI * pow(Frame_cosTheta(m), exponent);
		}
	}

	/* Prevent potential numerical issues in other stages of the model */
	if (result * Frame_cosTheta(m) < 1e-20)
		result = 0;

	return result;
}

/**
 * Smith's shadowing-masking function G1 for each
 * of the supported microfacet distributions
 *
 * \param v
 *     An arbitrary direction
 * \param m
 *     The microfacet normal
 */
Float distrSmithG1(MicrofacetType type, float alphaU, float alphaV, const Vector v, const Vector m) {
	/* Ensure consistent orientation (can't see the back of the microfacet from the front and vice versa) */
	if (dot(v, m) * Frame_cosTheta(v) <= 0)
		return 0.0;

	/* Perpendicular incidence -- no shadowing/masking */
	Float tanTheta = abs(Frame_tanTheta(v));
	if (tanTheta == 0.0)
		return 1.0;

	Float alpha = projectRoughness(alphaU, alphaV, v);
	if (type == Phong || type == Beckmann) {
	
		Float a = 1.0 / (alpha * tanTheta);
		if (a >= 1.6)
			return 1.0;

		/* Use a fast and accurate (<0.35% rel. error) rational
		   approximation to the shadowing-masking function */
		Float aSqr = a*a;
		return (3.535 * a + 2.181 * aSqr) / (1.0 + 2.276 * a + 2.577 * aSqr);
		
	} else { // GGX
		Float root = alpha * tanTheta;
		return 2.0 / (1.0 + hypot2(1.0, root));
	}
}

/**
 * Separable shadow-masking function based on Smith's
 * one-dimensional masking model
 */
Float distrG(MicrofacetType type, float alphaU, float alphaV, const Vector wi, const Vector wo, const Vector m) {
	return distrSmithG1(type, alphaU, alphaV, wi, m) * distrSmithG1(type, alphaU, alphaV, wo, m);
}

/**
 * Visible normal sampling code for the alpha=1 case
 *
 * Source: supplemental material of "Importance Sampling
 * Microfacet-Based BSDFs using the Distribution of Visible Normals"
 */
Vector2 sampleVisible11(MicrofacetType m_type, Float thetaI, Point2 sample1) {
	Vector2 slope;

	switch (m_type) {
		case Beckmann: {
			/* Special case (normal incidence) */
			if (thetaI < 1e-4f) {
				Float sinPhi, cosPhi;
				Float r = sqrt(-log(1.0-sample1.x));
				sincos(2 * M_PI * sample1.y, sinPhi, cosPhi);
				return Vector2(r * cosPhi, r * sinPhi);
			}

			/* The original inversion routine from the paper contained
			   discontinuities, which causes issues for QMC integration
			   and techniques like Kelemen-style MLT. The following code
			   performs a numerical inversion with better behavior */
			Float tanThetaI = tan(thetaI);
			Float cotThetaI = 1.0 / tanThetaI;

			/* Search interval -- everything is parameterized
			   in the erf() domain */
			Float a = -1, c = erf(cotThetaI);
			Float sample_x = max(sample1.x, 1e-6);

			/* Start with a good initial guess */
			//Float b = (1-sample_x) * a + sample_x * c;

			/* We can do better (inverse of an approximation computed in Mathematica) */
			Float fit = 1.0 + thetaI*(-0.876 + thetaI * (0.4265 - 0.0594*thetaI));
			Float b = c - (1.0+c) * pow(1.0-sample_x, fit);

			/* Normalization factor for the CDF */
			Float normalization = 1.0 / (1.0 + c + SQRT_PI_INV*tanThetaI*exp(-cotThetaI*cotThetaI));

			int it = 0;
			while (++it < 10) {
				/* Bisection criterion -- the oddly-looking
				   boolean expression are intentional to check
				   for NaNs at little additional cost */
				if (!(b >= a && b <= c))
					b = 0.5 * (a + c);

				/* Evaluate the CDF and its derivative
				   (i.e. the density function) */
				Float invErf = erfinv(b);
				Float value = normalization*(1 + b + SQRT_PI_INV*tanThetaI*exp(-invErf*invErf)) - sample_x;
				Float derivative = normalization * (1 - invErf*tanThetaI);

				if (abs(value) < 1e-5)
					break;

				/* Update bisection intervals */
				if (value > 0)
					c = b;
				else
					a = b;

				b -= value / derivative;
			}

			/* Now convert back into a slope value */
			slope.x = erfinv(b);

			/* Simulate Y component */
			slope.y = erfinv(2.0*max(sample1.y, 1e-6) - 1.0);
		};
		break;

		// case EGGX: {
		default: {
			/* Special case (normal incidence) */
			if (thetaI < 1e-4f) {
				Float sinPhi, cosPhi;
				Float r = sqrt(max(sample1.x / (1 - sample1.x), 0.0));
				sincos(2 * M_PI * sample1.y, sinPhi, cosPhi);
				return Vector2(r * cosPhi, r * sinPhi);
			}

			/* Precomputations */
			Float tanThetaI = tan(thetaI);
			Float a = 1 / tanThetaI;
			Float G1 = 2.0 / (1.0 + safe_sqrt(1.0 + 1.0 / (a*a)));

			/* Simulate X component */
			Float A = 2.0 * sample1.x / G1 - 1.0;
			if (abs(A) == 1)
				A -= sign(A)*Epsilon;
			Float tmp = 1.0 / (A*A - 1.0);
			Float B = tanThetaI;
			Float D = safe_sqrt(B*B*tmp*tmp - (A*A - B*B) * tmp);
			Float slope_x_1 = B * tmp - D;
			Float slope_x_2 = B * tmp + D;
			slope.x = (A < 0.0f || slope_x_2 > 1.0 / tanThetaI) ? slope_x_1 : slope_x_2;

			/* Simulate Y component */
			Float S;
			if (sample1.y > 0.5) {
				S = 1.0;
				sample1.y = 2.0 * (sample1.y - 0.5);
			} else {
				S = -1.0;
				sample1.y = 2.0 * (0.5 - sample1.y);
			}

			/* Improved fit */
			Float z =
				(sample1.y * (sample1.y * (sample1.y * (-0.365728915865723) + 0.790235037209296) -
					0.424965825137544) + 0.000152998850436920) /
				(sample1.y * (sample1.y * (sample1.y * (sample1.y * 0.169507819808272 - 0.397203533833404) -
					0.232500544458471) + 1) - 0.539825872510702);

			slope.y = S * z * sqrt(1.0 + slope.x*slope.x);
		};
	};
	return slope;
}

/**
 * Draw a sample from the distribution of visible normals
 * and return the associated probability density
 *
 * \param _wi
 *    A reference direction that defines the set of visible normals
 * \param sample
 *    A uniformly distributed 2D sample
 * \param pdf
 *    The probability density wrt. solid angles
 */
Normal sampleVisible(MicrofacetType type, float m_alphaU, float m_alphaV, const Vector _wi, const Point2 sample1) {
	/* Step 1: stretch wi */
	Vector wi = normalize(Vector(
		m_alphaU * _wi.x,
		m_alphaV * _wi.y,
		_wi.z
	));

	/* Get polar coordinates */
	Float theta = 0.0, phi = 0.0;
	if (wi.z < 0.99999) {
		theta = acos(wi.z);
		phi = atan2(wi.y, wi.x);
	}
	Float sinPhi = sin(phi), cosPhi = cos(phi);

	/* Step 2: simulate P22_{wi}(slope.x, slope.y, 1, 1) */
	Vector2 slope = sampleVisible11(type, theta, sample1);

	/* Step 3: rotate */
	slope = Vector2(
		cosPhi * slope.x - sinPhi * slope.y,
		sinPhi * slope.x + cosPhi * slope.y);

	/* Step 4: unstretch */
	slope.x *= m_alphaU;
	slope.y *= m_alphaV;

	/* Step 5: compute normal */
	Float normalization = 1.0 / sqrt(slope.x*slope.x + slope.y*slope.y + 1.0);

	return Normal(
		-slope.x * normalization,
		-slope.y * normalization,
		normalization
	);
}

// Implements the probability density of the function \ref sampleVisible()
Float pdfVisible(MicrofacetType type, float alphaU, float alphaV, float exponentU, float exponentV, const Vector wi, const Vector m) {
	if(Frame_cosTheta(wi) == 0)
		return 0.0;
	return distrSmithG1(type, alphaU, alphaV, wi, m) * abs(dot(wi, m)) * distrEval(type, alphaU, alphaV, exponentU, exponentV, m) / abs(Frame_cosTheta(wi));
}

/**
 * Wrapper function which calls \ref sampleAll() or \ref sampleVisible()
 * depending on the parameters of this class
 */
Normal distrSample(MicrofacetType type, float alphaU, float alphaV, float exponentU, float exponentV, const Vector wi, const Point2 sample1, inout Float pdf) {
	Normal m;
	//if (m_sampleVisible) {
		m = sampleVisible(type, alphaU, alphaV, wi, sample1);
		pdf = pdfVisible(type, alphaU, alphaV, exponentU, exponentV, wi, m);
	//} else {
	//	m = sampleAll(sample1, pdf);
	//}
	return m;
}

/**
 * Wrapper function which calls \ref sampleAll() or \ref sampleVisible()
 * depending on the parameters of this class
 */
Normal distrSample(MicrofacetType type, float alphaU, float alphaV, const Vector wi, const Point2 sample1) {
	Normal m;
	//if (m_sampleVisible) {
		m = sampleVisible(type, alphaU, alphaV, wi, sample1);
	//} else {
	//	Float pdf;
	//	m = sampleAll(sample, pdf);
	//}
	return m;
}


// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/libcore/util.cpp

Float fresnelConductorExact(Float cosThetaI, Float eta, Float k) {
	/* Modified from "Optics" by K.D. Moeller, University Science Books, 1988 */

	Float cosThetaI2 = cosThetaI*cosThetaI,
	      sinThetaI2 = 1-cosThetaI2,
		  sinThetaI4 = sinThetaI2*sinThetaI2;

	Float temp1 = eta*eta - k*k - sinThetaI2,
	      a2pb2 = sqrt(max(temp1*temp1 + 4*k*k*eta*eta, 0)),
	      a     = sqrt(max(0.5 * (a2pb2 + temp1), 0));

	Float term1 = a2pb2 + cosThetaI2,
	      term2 = 2*a*cosThetaI;

	Float Rs2 = (term1 - term2) / (term1 + term2);

	Float term3 = a2pb2*cosThetaI2 + sinThetaI4,
	      term4 = term2*sinThetaI2;

	Float Rp2 = Rs2 * (term3 - term4) / (term3 + term4);

	return 0.5 * (Rp2 + Rs2);
}

Spectrum fresnelConductorExact(Float cosThetaI, const Spectrum eta, const Spectrum k) {
	/* Modified from "Optics" by K.D. Moeller, University Science Books, 1988 */

	Float cosThetaI2 = cosThetaI*cosThetaI,
	      sinThetaI2 = 1.0-cosThetaI2,
		  sinThetaI4 = sinThetaI2*sinThetaI2;

	Spectrum temp1 = eta*eta - k*k - sinThetaI2,
	         a2pb2 = sqrt(max((temp1*temp1 + k*k*eta*eta*4.0), 0.0)),
	         a     = sqrt(max(((a2pb2 + temp1) * 0.5), 0.0));

	Spectrum term1 = a2pb2 + cosThetaI2,
	         term2 = a*(2.0*cosThetaI);

	Spectrum Rs2 = (term1 - term2) / (term1 + term2);

	Spectrum term3 = a2pb2*cosThetaI2 + sinThetaI4,
	         term4 = term2*sinThetaI2;

	Spectrum Rp2 = Rs2 * (term3 - term4) / (term3 + term4);

	return 0.5 * (Rp2 + Rs2);
}

#endif // DISTR_CGINC