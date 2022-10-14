#ifndef GPT_CGINC
#define GPT_CGINC

#include "RTLib.cginc"
#include "Surfel.cginc"
#include "Common.cginc"
#include "Distribution.cginc"

float3 _CameraPosition;
float4 _CameraRotation;
float2 _CameraUVSize;
float _Far;
int _FrameIndex;

#pragma max_recursion_depth 1

// miss shader, used when we don't hit any geometry
TextureCube _SkyBox;
SamplerState _LinearClamp;

#define Float float
#define Vector3 float3
#define Vector float3
#define Point3 float3
#define Spectrum float3

float3 SampleSky(float3 dir) {
    return _SkyBox.SampleLevel(_LinearClamp, dir, 0).rgb;
}

#define D_EPSILON 1e-14
// #define Epsilon 1e-4

#define m_strictNormals false
// depth to begin russian roulette
#define m_rrDepth 5
// min, max "recursive" depth
#define m_minDepth 0
#define m_maxDepth 12

// If defined, uses only the central sample for the throughput estimate. Otherwise uses offset paths for estimating throughput too.
// #define CENTRAL_RADIANCE

// Specifies the roughness threshold for classifying materials as 'diffuse', in contrast to 'specular', 
// for the purposes of constructing paths pairs for estimating pixel differences. This value should usually be somewhere between 0.0005 and 0.01. 
// If the result image has noise similar to standard path tracing, increasing or decreasing this value may sometimes help. This implementation assumes that this value is small.
#define m_shiftThreshold 0.001

float max3(float3 v) {
    return max(v.x, max(v.y, v.z));
}

enum ERadianceQuery: int {
    /// Emitted radiance from a luminaire intersected by the ray
    EEmittedRadiance = 0x0001,

    /// Emitted radiance from a subsurface integrator */
    ESubsurfaceRadiance = 0x0002,

    /// Direct (surface) radiance */
    EDirectSurfaceRadiance = 0x0004,

    /* Indirect (surface) radiance, where the last bounce did not go
    through a Dirac delta BSDF */
    EIndirectSurfaceRadiance = 0x0008,

    /* Indirect (surface) radiance, where the last bounce went
    through a Dirac delta BSDF */
    ECausticRadiance = 0x0010,

    /// In-scattered radiance due to volumetric scattering (direct)
    EDirectMediumRadiance = 0x0020,

    /// In-scattered radiance due to volumetric scattering (indirect)
    EIndirectMediumRadiance = 0x0040,

    /// Distance to the next surface intersection
    EDistance = 0x0080,

    /* A ray intersection may need to be performed. This can be set to
    zero if the caller has already provided the intersection */
    EIntersection = 0x0200,

    /// Radiance query without emitted radiance, ray intersection required
    ERadianceNoEmission = ESubsurfaceRadiance | EDirectSurfaceRadiance
         | EIndirectSurfaceRadiance | ECausticRadiance | EDirectMediumRadiance
         | EIndirectMediumRadiance | EIntersection,

    /// Default radiance query, ray intersection required
    ERadiance = ERadianceNoEmission | EEmittedRadiance,

};

#define EMeasure bool
const bool EDiscrete = false;
const bool ESolidAngle = true;

enum VertexType {
    VERTEX_TYPE_GLOSSY, ///< "Specular" vertex that requires the half-vector duplication shift.
    VERTEX_TYPE_DIFFUSE ///< "Non-specular" vertex that is rough enough for the reconnection shift.
};

enum RayConnection {
    RAY_NOT_CONNECTED, ///< Not yet connected - shifting in progress.
    RAY_RECENTLY_CONNECTED, ///< Connected, but different incoming direction so needs a BSDF evaluation.
    RAY_CONNECTED ///< Connected, allows using BSDF values from the base path.
};

struct Ray {
    float3 o; // origin
    float3 d; // direction
    float time;
    float mint;
    float maxt;
};

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/include/mitsuba/render/shape.h
// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/include/mitsuba/render/records.inl
struct Intersection {
    float t; // distance along ray
    float3 p; // point
    Frame geoFrame; // geometry frame = coordinate system along normal
    Frame shFrame; // shading frame = coordinate system along normal after normal mapping
    float3 wi; // incident direction in local shading frame
    bool hasUVPartials;
	bool isValid;
	bool isEmitter;
    float3 emission;// 0 if not emitter, else color
    bool isOnSurface;// sampleEmitterDirectVisible can lead to samples being taken from point lights; then it's false
    BSDF bsdf;
    // idc
    float time;
    uint randomSeed;
};

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/include/mitsuba/render/integrator.h
struct RadianceQueryRecord {
    int type; // query type
    int depth; // number of light bounces
    Intersection its;
    float alpha;
    float dist;
    int extra; // internal flag
};

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/integrators/gpt/gpt.cpp
struct RayState {
    Ray ray;
    RadianceQueryRecord rRec; // The radiance query record for this ray.
    float3 radiance; // = 0; // accumulated
    float3 gradient; // = 0; // accumulated
    float3 throughput; // = 0;
    float pdf; // = 1.0;
    bool alive; // = true;
    float eta; // refractive index of ray
    RayConnection connection_status;
};

/// Result of a reconnection shift.
struct ReconnectionShiftResult {
    bool success; ///< Whether the shift succeeded.
    float jacobian; ///< Local Jacobian determinant of the shift.
    Vector3 wo; ///< World space outgoing vector for the shift.
};

/// Result of a half-vector duplication shift.
struct HalfVectorShiftResult {
    bool success; ///< Whether the shift succeeded.
    float jacobian; ///< Local Jacobian determinant of the shift.
    Vector3 wo; ///< Tangent space outgoing vector for the shift.
};

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/include/mitsuba/render/common.h
// Specifies the transport mode when sampling or evaluating a scattering function
/*enum ETransportMode: int {
	/// Radiance transport
	ERadiance = 0, // already defined by other enum
	/// Importance transport
	EImportance = 1,
	/// Specifies the number of supported transport modes
	ETransportModes = 2
};*/
bool ETransportRadiance = false;
bool ETransportImportance = true;

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/include/mitsuba/render/bsdf.h
struct BSDFSamplingRecord {
	Intersection its;
	float3 wi;
	float3 wo;
	bool mode; // radiance or importance; required for non-reciprocal (?) BSDFs as transmission through dielectric materials
	int sampledType;
    float eta;
};

/// Stores the results of a BSDF sample.
/// Do not confuse with Mitsuba's BSDFSamplingRecord.
struct BSDFSampleResult {
	BSDFSamplingRecord bRec;  ///< The corresponding BSDF sampling record.
	Spectrum weight;          ///< BSDF weight of the sampled direction.
	float pdf;                ///< PDF of the BSDF sample.
};

struct PositionSamplingRecord {
	float3 p;
	float time;
	float3 n;
	float pdf;
	EMeasure measure;
	float2 uv;
    Intersection its;
	// object.. which could be an emitter
};

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/include/mitsuba/render/common.h
struct DirectSamplingRecord : PositionSamplingRecord {
	float3 ref;
	float3 refN;
	float3 d;
	float dist;
    float pdf;
};

bool isZero(const float3 v) {
    return v.x == 0 && v.y == 0 && v.z == 0;
}

float3 toWorld(const Frame f, const float3 v){
	return quatRot(v, f);
}

float3 toLocal(const Frame f, const float3 v){
	return quatRotInv(v, f);
}

float lengthSquared(const float3 v) {
    return dot(v, v);
}

float3 toWorld(const Intersection its, const float3 v){
	return toWorld(its.shFrame, v);
}

float3 toLocal(const Intersection its, const float3 v){
	return toLocal(its.shFrame, v);
}

bool rayIntersect(Ray ray, inout Intersection its) {

    RayDesc rayDesc = (RayDesc) 0;
    rayDesc.Origin = ray.o;
    rayDesc.Direction = ray.d;
    rayDesc.TMin = ray.mint;
    rayDesc.TMax = ray.maxt;

    RayPayload rayPayload = (RayPayload) 0;
    rayPayload.distance = ray.maxt;
    rayPayload.depth = 0;
    rayPayload.gpt = true;

    // default values for bsdf
    rayPayload.bsdf.eta = 1.0;
    rayPayload.bsdf.numComponents = 0;
    rayPayload.randomSeed = its.randomSeed;

    TraceRay(_RaytracingAccelerationStructure, RAY_FLAG_NONE,
			RAYTRACING_OPAQUE_FLAG, 0, 1, 0, rayDesc, rayPayload);

    its.p = ray.o + ray.d * rayPayload.distance;
    its.t = rayPayload.distance;

	bool sky = its.t >= ray.maxt;
    its.isOnSurface = !sky; // returns false at sky
    its.isValid = !sky;
    its.geoFrame = rayPayload.geoFrame;
    its.shFrame = rayPayload.shFrame;
    its.randomSeed = rayPayload.randomSeed;
    // wi is defined as being from the surface towards the ray origin:
    // https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/include/mitsuba/render/skdtree.h#L427
    its.wi = toLocal(its, -ray.d);
    its.isEmitter = rayPayload.bsdf.materialType == AREA_LIGHT;
    its.bsdf = rayPayload.bsdf;

    its.bsdf.type = 0;
    for(int i=0;i<its.bsdf.numComponents;i++){
        its.bsdf.type |= its.bsdf.components[i].type;
    }

	return its.isValid;
}

bool rayIntersect(inout RadianceQueryRecord rec, Ray ray){
	return rayIntersect(ray, rec.its);
}

void sendTrace(inout Intersection its, inout Ray ray){
    rayIntersect(ray, its);
}

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/include/mitsuba/render/shape.h
BSDF getBSDF(inout Intersection its, inout Ray ray) {
    // ray matching is guranteed
    // if(ray != its.ray) sendTrace(its, ray);
    return its.bsdf;
}

float pdfEmitterDirect(DirectSamplingRecord rec){
    return rec.pdf;
}

#include "Materials.cginc"

// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/include/mitsuba/render/bsdf.h
// ~ line 400

// eval and pdf don't necessarily are the same as the original ray
// sample: shiftedBsdfValue = eval(shiftedBSDF, bRec), where bRec.wo = toLocal(someIts, emitterDirection), and emitterDirection = some calculation (line 894)
// there are two possible solutions:
// - 1) encode the BSDF in RayPayload, 
// - 2) trace another ray

float3 eval(inout BSDF bsdf, inout BSDFSamplingRecord rec, bool measure) {
    switch(bsdf.materialType){
        case CONDUCTOR:
            return Conductor_eval(bsdf,rec,measure);
        case ROUGH_CONDUCTOR:
            return RoughConductor_eval(bsdf,rec,measure);
        case DIFFUSE:
            return Diffuse_eval(bsdf,rec,measure);
        case ROUGH_DIFFUSE:
            return RoughDiffuse_eval(bsdf,rec,measure);
        case DIELECTRIC:
            return Dielectric_eval(bsdf,rec,measure);
        case ROUGH_DIELECTRIC:
            return RoughDielectric_eval(bsdf,rec,measure);
        case AREA_LIGHT:
            return bsdf.color;
        default:
            return 0;
    }
}

float pdf(inout BSDF bsdf, inout BSDFSamplingRecord rec, EMeasure measure) {
    switch(bsdf.materialType){
        case CONDUCTOR:
            return Conductor_pdf(bsdf,rec,measure);
        case ROUGH_CONDUCTOR:
            return RoughConductor_pdf(bsdf,rec,measure);
        case DIFFUSE:
            return Diffuse_pdf(bsdf,rec,measure);
        case ROUGH_DIFFUSE:
            return RoughDiffuse_pdf(bsdf,rec,measure);
        case DIELECTRIC:
            return Dielectric_pdf(bsdf,rec,measure);
        case ROUGH_DIELECTRIC:
            return RoughDielectric_pdf(bsdf,rec,measure);
        case AREA_LIGHT:
            return 0.0;
        default:
            return 0;
    }
}

/**
 * draws a random sample from the BSDF (= random direction from the outgoing lobe);
 * in contrast to eval() and pdf(), which use a pre-determined outgoing direction
 */
float3 sample1(inout BSDF bsdf, inout BSDFSamplingRecord rec, out float pdf, float2 random) {
    rec.eta = 1.0;
    switch(bsdf.materialType){
        case CONDUCTOR:
            return Conductor_sample(bsdf,rec,pdf,random);
        case ROUGH_CONDUCTOR:
            return RoughConductor_sample(bsdf,rec,pdf,random);
        case DIFFUSE:
            return Diffuse_sample(bsdf,rec,pdf,random);
        case ROUGH_DIFFUSE:
            return RoughDiffuse_sample(bsdf,rec,pdf,random);
        case DIELECTRIC:
            return Dielectric_sample(bsdf,rec,pdf,random);
        case ROUGH_DIELECTRIC:
            return RoughDielectric_sample(bsdf,rec,pdf,random);
        case AREA_LIGHT:
            pdf = 1.0;
            rec.wo = rec.wi;
            return bsdf.color;
        default:
            pdf = 0;
            return 0;
    }
}

float3 eval(inout BSDF bsdf, inout BSDFSamplingRecord rec) {
    return eval(bsdf, rec, ESolidAngle);
}

float pdf(inout BSDF bsdf, inout BSDFSamplingRecord rec) {
    return pdf(bsdf, rec, ESolidAngle);
}

bool testVisibility(float3 a, float3 b, float time) {
    // raycast to determine visibility
	RayDesc rayDesc = (RayDesc) 0;
	float3 dir = b-a;
	float dist = min(_Far, length(dir));
	rayDesc.Origin = a;
	rayDesc.Direction = normalize(dir);
	rayDesc.TMin = 0.01 * dist;
	rayDesc.TMax = 0.99 * dist;
	RayPayload rayPayload = (RayPayload) 0;
    rayPayload.gpt = true;
	rayPayload.distance = max(_Far, dist * 2.0); // set to infinity at start
	TraceRay(_RaytracingAccelerationStructure,
				RAY_FLAG_ACCEPT_FIRST_HIT_AND_END_SEARCH,// | RAY_FLAG_CULL_BACK_FACING_TRIANGLES, // todo is this correct?
				RAYTRACING_OPAQUE_FLAG, 0, 1, 0, rayDesc, rayPayload);
    return rayPayload.distance >= dist;
}

// light sample data
float _LightAccuArea;
StructuredBuffer<Triangle> g_Triangles;

#include "SampleTri.cginc"

void sampleEmitterDirectVisible(inout DirectSamplingRecord rec, float2 random, out float3 emitterRadiance, out bool mainEmitterVisible) {
    // todo do we need to write more information?
    float relativeIndex = random.x * _LightAccuArea;
    emitterRadiance = 0;
    rec.pdf = 0;

    // make seed depend on more parameters, maybe on random
    uint index = DispatchRaysIndex().x;
    uint randomSeed = initRand(index ^ 0xffff + DispatchRaysIndex().y, _FrameIndex ^ (int) (random.x * 0xffffff));

    if(FindEmissiveTriangle(relativeIndex, rec.p, rec.d, emitterRadiance, randomSeed)){
        // check visibility
        // what is the start position? rec.ref, which is being set in the constructor of DirectSamplingRecord
        mainEmitterVisible = testVisibility(rec.ref, rec.p, 0.0);
        if(mainEmitterVisible){
            // todo is this the correct probability?
            rec.pdf = 0.1;
            return;
        }
    }
    mainEmitterVisible = false;
}

// Environment(Emitter).fillDirectSamplingRecord
// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/include/mitsuba/render/emitter.h, line 600
bool fillDirectSamplingRecord(inout DirectSamplingRecord rec, Ray ray){
    // ensure the ray is valid
    rec.p = rec.its.p;
    rec.n = Frame_n(rec.its.shFrame);
    // find out what the measure is
    // should be fine as long as this is the only component...
    rec.measure = ((rec.its.bsdf.components[0].type & ESmooth) != 0) ? ESolidAngle : EDelta;
    rec.d = ray.d;
    rec.dist = rec.its.t;
    // todo is this correct?
    rec.pdf = 1.0; // rec.its.bsdf.sampledPdf;
    return true;
}

DirectSamplingRecord createDirectSamplingRecord(const Intersection its){
    DirectSamplingRecord rec = (DirectSamplingRecord) 0;
    rec.its = its;
    rec.ref = its.p;
    if((its.bsdf.type & (ETransmission | EBackSide)) == 0)
        rec.refN = Frame_n(its.shFrame);
    return rec;
}

float getRoughness(BSDF bsdf, Intersection its, int componentIndex){
    return bsdf.components[componentIndex].roughness;
}

// calls Emitter.eval(its, dir)
// https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/include/mitsuba/render/emitter.h#L482
float3 Le(Intersection its, float3 dir){
    // light emitted at intersection in direction dir
    // question:
    //   is this truly constant? look at different lights, and decide whether a constant is good enough
    //   https://github.com/mmanzi/gradientdomain-mitsuba/tree/c7c94e66e17bc41cca137717971164de06971bc7/src/emitters
    // answer:
    //   https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/emitters/area.cpp#L104
    //   https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/src/emitters/constant.cpp#L102
    //   environment is more complex, but we handle that separately
    //   not defined in other classes -> we're done here :)
    if (dot(Frame_n(its.shFrame), dir) <= 0.0)
		return 0.0;
	else
		return its.emission;
}

float nextSample1D(inout RadianceQueryRecord r){
    return nextRand(r.its.randomSeed);
}

float2 nextSample2D(inout RadianceQueryRecord r){
    return float2(nextRand(r.its.randomSeed),nextRand(r.its.randomSeed));
}

bool testEnvironmentVisibility(Ray ray) {
    // is the sky visible from this point/direction?
    return testVisibility(ray.o, ray.o + _Far * normalize(ray.d), 0.0);
}

float3 evalEnvironment(Ray ray){
	return SampleSky(ray.d);
}

// where is the weight increased?
void addRadiance(inout RayState r, float3 color, float weight){
	r.radiance += color * weight;
}

void addGradient(inout RayState r, float3 color, float weight){
	r.gradient += color * weight;
}

/// Calculates the outgoing direction of a shift by duplicating the local half-vector.
HalfVectorShiftResult halfVectorShift(Vector3 tangentSpaceMainWi, Vector3 tangentSpaceMainWo, Vector3 tangentSpaceShiftedWi, float mainEta, float shiftedEta) {
    HalfVectorShiftResult result;

    if (Frame_cosTheta(tangentSpaceMainWi) * Frame_cosTheta(tangentSpaceMainWo) < 0) {
        // Refraction.

        // Refuse to shift if one of the Etas is exactly 1. This causes degenerate half-vectors.
        if (mainEta == 1 || shiftedEta == 1) {
            // This could be trivially handled as a special case if ever needed.
            result.success = false;
            return result;
        }

        // Get the non-normalized half vector.
        Vector3 tangentSpaceHalfVectorNonNormalizedMain;
        if (Frame_cosTheta(tangentSpaceMainWi) < 0) {
            tangentSpaceHalfVectorNonNormalizedMain = -(tangentSpaceMainWi * mainEta + tangentSpaceMainWo);
        } else {
            tangentSpaceHalfVectorNonNormalizedMain = -(tangentSpaceMainWi + tangentSpaceMainWo * mainEta);
        }

        // Get the normalized half vector.
        Vector3 tangentSpaceHalfVector = normalize(tangentSpaceHalfVectorNonNormalizedMain);

        // Refract to get the outgoing direction.
        Vector3 tangentSpaceShiftedWo = refract1(tangentSpaceShiftedWi, tangentSpaceHalfVector, shiftedEta);

        // Refuse to shift between transmission and full internal reflection.
        // This shift would not be invertible: reflections always shift to other reflections.
        if (isZero(tangentSpaceShiftedWo)) {
            result.success = false;
            return result;
        }

        // Calculate the Jacobian.
        Vector3 tangentSpaceHalfVectorNonNormalizedShifted;
        if (Frame_cosTheta(tangentSpaceShiftedWi) < 0) {
            tangentSpaceHalfVectorNonNormalizedShifted =  - (tangentSpaceShiftedWi * shiftedEta + tangentSpaceShiftedWo);
        } else {
            tangentSpaceHalfVectorNonNormalizedShifted =  - (tangentSpaceShiftedWi + tangentSpaceShiftedWo * shiftedEta);
        }

        float hLengthSquared = lengthSquared(tangentSpaceHalfVectorNonNormalizedShifted) / (D_EPSILON + lengthSquared(tangentSpaceHalfVectorNonNormalizedMain));
        float WoDotH = abs(dot(tangentSpaceMainWo, tangentSpaceHalfVector)) / (D_EPSILON + abs(dot(tangentSpaceShiftedWo, tangentSpaceHalfVector)));

        // Output results.
        result.success = true;
        result.wo = tangentSpaceShiftedWo;
        result.jacobian = hLengthSquared * WoDotH;
    } else {
        // Reflection.
        Vector3 tangentSpaceHalfVector = normalize(tangentSpaceMainWi + tangentSpaceMainWo);
        Vector3 tangentSpaceShiftedWo = reflect1(tangentSpaceShiftedWi, tangentSpaceHalfVector);

        float WoDotH = dot(tangentSpaceShiftedWo, tangentSpaceHalfVector) / dot(tangentSpaceMainWo, tangentSpaceHalfVector);
        float jacobian = abs(WoDotH);

        result.success = true;
        result.wo = tangentSpaceShiftedWo;
        result.jacobian = jacobian;
    }

    return result;
}

/// Tries to connect the offset path to a specific vertex of the main path.
ReconnectionShiftResult reconnectShift(Point3 mainSourceVertex, Point3 targetVertex, Point3 shiftSourceVertex, Vector3 targetNormal, float time) {
    ReconnectionShiftResult result;

    // Check visibility of the connection.
    if (!testVisibility(shiftSourceVertex, targetVertex, time)) {
        // Since this is not a light sample, we cannot allow shifts through occlusion.
        result.success = false;
        return result;
    }

    // Calculate the Jacobian.
    Vector3 mainEdge = mainSourceVertex - targetVertex;
    Vector3 shiftedEdge = shiftSourceVertex - targetVertex;

    float mainEdgeLengthSquared = lengthSquared(mainEdge);
    float shiftedEdgeLengthSquared = lengthSquared(shiftedEdge);

    Vector3 shiftedWo = -shiftedEdge / sqrt(shiftedEdgeLengthSquared);

    float mainOpposingCosine = dot(mainEdge, targetNormal) / sqrt(mainEdgeLengthSquared);
    float shiftedOpposingCosine = dot(shiftedWo, targetNormal);

    float jacobian = abs(shiftedOpposingCosine * mainEdgeLengthSquared) / (D_EPSILON + abs(mainOpposingCosine * shiftedEdgeLengthSquared));

    // Return the results.
    result.success = true;
    result.jacobian = jacobian;
    result.wo = shiftedWo;
    return result;
}

/// Tries to connect the offset path to a the environment emitter.
ReconnectionShiftResult environmentShift(Ray mainRay, Point3 shiftSourceVertex) {

    ReconnectionShiftResult result;

    // Check visibility of the environment.
    Ray offsetRay = mainRay;
    offsetRay.o = shiftSourceVertex;

    if (!testEnvironmentVisibility(offsetRay)) {
        // Environment was occluded.
        result.success = false;
        return result;
    }

    // Return the results.
    result.success = true;
    result.jacobian = 1.0;
    result.wo = mainRay.d;

    return result;
}

/// Returns the vertex type of a vertex by its roughness value.
VertexType getVertexTypeByRoughness(float roughness) {
	if(roughness <= m_shiftThreshold) {
		return VERTEX_TYPE_GLOSSY;
	} else {
		return VERTEX_TYPE_DIFFUSE;
	}
}

/// Returns the vertex type (diffuse / glossy) of a vertex, for the purposes of determining
/// the shifting strategy.
///
/// A bare classification by roughness alone is not good for multi-component BSDFs since they
/// may contain a diffuse component and a perfect specular component. If the base path
/// is currently working with a sample from a BSDF's smooth component, we don't want to care
/// about the specular component of the BSDF right now - we want to deal with the smooth component.
///
/// For this reason, we vary the classification a little bit based on the situation.
/// This is perfectly valid, and should be done.
VertexType getVertexType(const BSDF bsdf, Intersection its, unsigned int bsdfType) {
	// Return the lowest roughness value of the components of the vertex's BSDF.
	// If 'bsdfType' does not have a delta component, do not take perfect speculars (zero roughness) into account in this.

	float lowest_roughness = 1e10;

	bool found_smooth = false;
	bool found_dirac = false;
	for(int i = 0; i < bsdf.numComponents; i++) {
		float component_roughness = getRoughness(bsdf, its, i);

		if(component_roughness == 0.0) {
			found_dirac = true;
			if(!(bsdfType & EDelta)) {
				// Skip Dirac components if a smooth component is requested.
				continue;
			}
		} else {
			found_smooth = true;
		}

		if(component_roughness < lowest_roughness) {
			lowest_roughness = component_roughness;
		}
	}

	// Roughness has to be zero also if there is a delta component but no smooth components.
	if(!found_smooth && found_dirac && !(bsdfType & EDelta)) {
        lowest_roughness = 0.0;
	}

	return getVertexTypeByRoughness(lowest_roughness);
}

VertexType getVertexType(RayState ray, unsigned int bsdfType) {
	return getVertexType(getBSDF(ray.rRec.its, ray.ray), ray.rRec.its, bsdfType);
}

/// Samples a direction according to the BSDF at the given ray position.
BSDFSampleResult sampleBSDF(inout RayState rayState) {

	// Note: If the base path's BSDF evaluation uses random numbers, it would be beneficial to use the same random numbers for the offset path's BSDF.
	//       This is not done currently.
	BSDF bsdf = getBSDF(rayState.rRec.its, rayState.ray);

	// Sample BSDF * cos(theta).
	BSDFSampleResult result = (BSDFSampleResult) 0;
	result.bRec.its = rayState.rRec.its;
    result.bRec.wi = toLocal(rayState.rRec.its.shFrame, -rayState.ray.d);
    // extra sampler for some BSDFs; according to
    // https://github.com/mmanzi/gradientdomain-mitsuba/blob/c7c94e66e17bc41cca137717971164de06971bc7/include/mitsuba/render/bsdf.h, line 126,
    // this can improve the quality; all this does is generating random numbers
    // result.bRec.? = rayState.rRec.sampler;
    result.bRec.mode = ERadiance;

	result.weight = sample1(bsdf, result.bRec, result.pdf, nextSample2D(rayState.rRec));

	// Variable result.pdf will be 0 if the BSDF sampler failed to produce a valid direction.
	// SAssert(result.pdf <= (Float)0 || fabs(result.bRec.wo.length() - 1.0) < 0.00001);
	return result;
}

#define SURFELS_ONLY

/// Constructs a sequence of base paths and shifts them into offset paths, evaluating their throughputs and differences.
/// This is the core of the rendering algorithm.
bool evaluate(inout RayState main, inout RayState shiftedRays[4], int secondaryCount, inout Spectrum out_veryDirect) {

    // Perform the first ray intersection for the base path (or ignore if the intersection has already been provided).
    rayIntersect(main.rRec, main.ray);
    main.ray.mint = Epsilon;
    main.ray.maxt = _Far;

    if (!main.rRec.its.isValid) {
        // First hit is not in the scene so can't continue. Also there there are no paths to shift.

        // Add potential very direct light from the environment as gradients are not used for that.
        // Removed for surfels, as this will be ignored anyway
        #ifndef SURFELS_ONLY
        if (main.rRec.type & EEmittedRadiance) {
            out_veryDirect += main.throughput * evalEnvironment(main.ray);
        }
        #endif

        //SLog(EInfo, "Main ray(%d): First hit not in scene.", rayCount);
        // false, because not allowed for surfels: the first ray must hit!
        return false;
    }

    // Perform the same first ray intersection for the offset paths.
    for (int i = 0; i < secondaryCount; i++) {
        rayIntersect(shiftedRays[i].rRec, shiftedRays[i].ray);
        shiftedRays[i].ray.mint = Epsilon;
        shiftedRays[i].ray.maxt = _Far;
    }

    // Add very direct light from non-environment.
    // Include emitted radiance if requested.
    if (main.rRec.its.isEmitter && (main.rRec.type & EEmittedRadiance)) {
        out_veryDirect += main.throughput * Le(main.rRec.its, -main.ray.d);
    }

    // If no intersection of an offset ray could be found, its offset paths can not be generated.
    for (int i = 0; i < secondaryCount; i++) {
        if (!shiftedRays[i].rRec.its.isValid) {
            shiftedRays[i].alive = false;
            // can be used to debug how successful the first shifted rays are;
            // in the original GPT, these rays were well defined to be at 1px offset, however with surfels,
            // they can have varying directions and origins
            // out_veryDirect.x++;
        }
    }

    // for debugging
    // out_veryDirect += Frame_n(main.rRec.its.shFrame)*.5+.5;
    // float f = dot(main.ray.d, Frame_n(main.rRec.its.geoFrame)) * Frame_cosTheta(main.rRec.its.wi);
    // out_veryDirect += f*.5+.5;
    // if(f >= 0) out_veryDirect.z++;
    // return true;

    // Strict normals check to produce the same results as bidirectional methods when normal mapping is used.
    if (m_strictNormals) {
        // If 'strictNormals'=true, when the geometric and shading normals classify the incident direction to the same side, then the main path is still good.
        if (dot(main.ray.d, Frame_n(main.rRec.its.geoFrame)) * Frame_cosTheta(main.rRec.its.wi) >= 0) {
            // This is an impossible base path.
            // this can also happen if the front side of the surfel cannot be seen from the camera
            // out_veryDirect.z+=Frame_cosTheta(main.rRec.its.wi);
            return false;
        }

        for (int i = 0; i < secondaryCount; i++) {
            if (dot(shiftedRays[i].ray.d, Frame_n(shiftedRays[i].rRec.its.geoFrame)) * Frame_cosTheta(shiftedRays[i].rRec.its.wi) >= 0) {
                // This is an impossible offset path.
                shiftedRays[i].alive = false;
            }
        }
    }

    // for debugging
    // out_veryDirect.y++;

    // Main path tracing loop.
    main.rRec.depth = 1;
    while (main.rRec.depth < m_maxDepth) {

        // Strict normals check to produce the same results as bidirectional methods when normal mapping is used.
        // If 'strictNormals'=true, when the geometric and shading normals classify the incident direction to the same side, then the main path is still good.
        if (m_strictNormals) {
            if (dot(main.ray.d, Frame_n(main.rRec.its.geoFrame)) * Frame_cosTheta(main.rRec.its.wi) >= 0) {
                // This is an impossible main path, and there are no more paths to shift.
                // happens rarely;
                return true;
            }

            for (int i = 0; i < secondaryCount; i++) {
                if (dot(shiftedRays[i].ray.d, Frame_n(shiftedRays[i].rRec.its.geoFrame)) * Frame_cosTheta(shiftedRays[i].rRec.its.wi) >= 0) {
                    // This is an impossible offset path.
                    shiftedRays[i].alive = false;
                }
            }
        }

        // Some optimizations can be made if this is the last traced segment.
        bool lastSegment = (main.rRec.depth + 1 == m_maxDepth);

        /* ==================================================================== */
        /*                     Direct illumination sampling                     */
        /* ==================================================================== */

        // Sample incoming radiance from lights (next event estimation).
        {
            BSDF mainBSDF = getBSDF(main.rRec.its, main.ray);
            if (main.rRec.type & EDirectSurfaceRadiance && mainBSDF.type & ESmooth && main.rRec.depth + 1 >= m_minDepth) {
                // Sample an emitter and evaluate f = f/p * p for it. */
                DirectSamplingRecord dRec = createDirectSamplingRecord(main.rRec.its);

                float2 lightSample = nextSample2D(main.rRec);

				float3 emitterRadiance;
                bool mainEmitterVisible;
				sampleEmitterDirectVisible(dRec, lightSample, emitterRadiance, mainEmitterVisible);

                Spectrum mainEmitterRadiance = emitterRadiance * dRec.pdf;

                // const Emitter * emitter = static_cast < const Emitter *  > (dRec.object);
				// Emitter emitter = dRec.object;

                // If the emitter sampler produces a non-emitter, that's a problem.
                // SAssert(emitter != nullptr);

                // Add radiance and gradients to the base path and its offset path.
                // Query the BSDF to the emitter's direction.
                BSDFSamplingRecord mainBRec = (BSDFSamplingRecord) 0;
                mainBRec.its = main.rRec.its;
                mainBRec.wo = toLocal(main.rRec.its, dRec.d);
                mainBRec.mode = ERadiance;

                // Evaluate BSDF * cos(theta).
                Spectrum mainBSDFValue = eval(mainBSDF, mainBRec);

                // Calculate the probability density of having generated the sampled path segment by BSDF sampling. Note that if the emitter is not visible, the probability density is zero.
                // Even if the BSDF sampler has zero probability density, the light sampler can still sample it.
                float mainBsdfPdf = (dRec.its.isOnSurface && dRec.measure == ESolidAngle && mainEmitterVisible) ? pdf(mainBSDF, mainBRec) : 0;

                // There values are probably needed soon for the Jacobians.
                float mainDistanceSquared = lengthSquared(main.rRec.its.p - dRec.p);
                float mainOpposingCosine = dot(dRec.n, (main.rRec.its.p - dRec.p)) / sqrt(mainDistanceSquared);

                // Power heuristic weights for the following strategies: light sample from base, BSDF sample from base.
                float mainWeightNumerator = main.pdf * dRec.pdf;
                float mainWeightDenominator = (main.pdf * main.pdf) * ((dRec.pdf * dRec.pdf) + (mainBsdfPdf * mainBsdfPdf));

#ifdef CENTRAL_RADIANCE
                addRadiance(main, main.throughput * (mainBSDFValue * mainEmitterRadiance), mainWeightNumerator / (D_EPSILON + mainWeightDenominator));
#endif

                // Strict normals check to produce the same results as bidirectional methods when normal mapping is used.
                if (!m_strictNormals || dot(Frame_n(main.rRec.its.geoFrame), dRec.d) * Frame_cosTheta(mainBRec.wo) > 0) {
                    // The base path is good. Add radiance differences to offset paths.
                    for (int i = 0; i < secondaryCount; i++) {
                        // Evaluate and apply the gradient.

                        Spectrum mainContribution = 0.0;
                        Spectrum shiftedContribution = 0.0;
                        float weight = 0.0;

                        bool shiftSuccessful = shiftedRays[i].alive;

                        // Construct the offset path.
                        if (shiftSuccessful) {
                            // Generate the offset path.
                            if (shiftedRays[i].connection_status == RAY_CONNECTED) {
                                // Follow the base path. All relevant vertices are shared.
                                float shiftedBsdfPdf = mainBsdfPdf;
                                float shiftedDRecPdf = dRec.pdf;
                                Spectrum shiftedBsdfValue = mainBSDFValue;
                                Spectrum shiftedEmitterRadiance = mainEmitterRadiance;
                                float jacobian = 1;

                                // Power heuristic between light sample from base, BSDF sample from base, light sample from offset, BSDF sample from offset.
                                float shiftedWeightDenominator = (jacobian * shiftedRays[i].pdf) * (jacobian * shiftedRays[i].pdf) * ((shiftedDRecPdf * shiftedDRecPdf) + (shiftedBsdfPdf * shiftedBsdfPdf));
                                weight = mainWeightNumerator / (D_EPSILON + shiftedWeightDenominator + mainWeightDenominator);

                                mainContribution = main.throughput * (mainBSDFValue * mainEmitterRadiance);
                                shiftedContribution = jacobian * shiftedRays[i].throughput * (shiftedBsdfValue * shiftedEmitterRadiance);

                                // Note: The Jacobians were baked into shiftedRays[i].pdf and shiftedRays[i].throughput at connection phase.
                            } else if (shiftedRays[i].connection_status == RAY_RECENTLY_CONNECTED) {
                                // Follow the base path. The current vertex is shared, but the incoming directions differ.
                                Vector3 incomingDirection = normalize(shiftedRays[i].rRec.its.p - main.rRec.its.p);

                                BSDFSamplingRecord bRec;
								bRec.its = main.rRec.its;
								bRec.wi = toLocal(main.rRec.its, incomingDirection);
								bRec.wo = toLocal(main.rRec.its, dRec.d);
								bRec.mode = ETransportRadiance;

                                // Sample the BSDF.
                                float shiftedBsdfPdf = (dRec.its.isOnSurface && dRec.measure == ESolidAngle && mainEmitterVisible) ? pdf(mainBSDF, bRec) : 0; // The BSDF sampler can not sample occluded path segments.
                                float shiftedDRecPdf = dRec.pdf;
                                Spectrum shiftedBsdfValue = eval(mainBSDF, bRec);
                                Spectrum shiftedEmitterRadiance = mainEmitterRadiance;
                                float jacobian = 1;

                                // Power heuristic between light sample from base, BSDF sample from base, light sample from offset, BSDF sample from offset.
                                float shiftedWeightDenominator = (jacobian * shiftedRays[i].pdf) * (jacobian * shiftedRays[i].pdf) * ((shiftedDRecPdf * shiftedDRecPdf) + (shiftedBsdfPdf * shiftedBsdfPdf));
                                weight = mainWeightNumerator / (D_EPSILON + shiftedWeightDenominator + mainWeightDenominator);

                                mainContribution = main.throughput * (mainBSDFValue * mainEmitterRadiance);
                                shiftedContribution = jacobian * shiftedRays[i].throughput * (shiftedBsdfValue * shiftedEmitterRadiance);

                                // Note: The Jacobians were baked into shiftedRays[i].pdf and shiftedRays[i].throughput at connection phase.
                            } else {
                                // shiftedRays[i].connection_status == RAY_NOT_CONNECTED
                                // Reconnect to the sampled light vertex. No shared vertices.

                                BSDF shiftedBSDF = getBSDF(shiftedRays[i].rRec.its, shiftedRays[i].ray);

                                // This implementation uses light sampling only for the reconnect-shift.
                                // When one of the BSDFs is very glossy, light sampling essentially reduces to a failed shift anyway.
                                bool mainAtPointLight = (dRec.measure == EDiscrete);

                                VertexType mainVertexType = getVertexType(main, ESmooth);
                                VertexType shiftedVertexType = getVertexType(shiftedRays[i], ESmooth);

                                if (mainAtPointLight || (mainVertexType == VERTEX_TYPE_DIFFUSE && shiftedVertexType == VERTEX_TYPE_DIFFUSE)) {

                                    // Get emitter radiance.
                                    DirectSamplingRecord shiftedDRec = createDirectSamplingRecord(shiftedRays[i].rRec.its);
                                    
                                    // std::pair<Spectrum, bool> emitterTuple = 
                                    bool shiftedEmitterVisible;
									float emitterRadiance;
									sampleEmitterDirectVisible(shiftedDRec, lightSample, emitterRadiance, shiftedEmitterVisible);

                                    Spectrum shiftedEmitterRadiance = emitterRadiance * shiftedDRec.pdf;
                                    float shiftedDRecPdf = shiftedDRec.pdf;

                                    // Sample the BSDF.
                                    float shiftedDistanceSquared = lengthSquared(dRec.p - shiftedRays[i].rRec.its.p);
                                    Vector emitterDirection = (dRec.p - shiftedRays[i].rRec.its.p) / sqrt(shiftedDistanceSquared);
                                    float shiftedOpposingCosine = -dot(dRec.n, emitterDirection);

                                    BSDFSamplingRecord bRec = (BSDFSamplingRecord) 0;
									bRec.its = shiftedRays[i].rRec.its;
									bRec.wo = toLocal(shiftedRays[i].rRec.its, emitterDirection);
									bRec.mode = ETransportRadiance;

                                    // Strict normals check, to make the output match with bidirectional methods when normal maps are present.
                                    if (m_strictNormals && dot(Frame_n(shiftedRays[i].rRec.its.geoFrame), emitterDirection) * Frame_cosTheta(bRec.wo) < 0) {
                                        // Invalid, non-samplable offset path.
                                        shiftSuccessful = false;
                                    } else {
                                        Spectrum shiftedBsdfValue = eval(shiftedBSDF, bRec);
                                        float shiftedBsdfPdf = (dRec.its.isOnSurface && dRec.measure == ESolidAngle && shiftedEmitterVisible) ? pdf(shiftedBSDF, bRec) : 0;
                                        float jacobian = abs(shiftedOpposingCosine * mainDistanceSquared) / (Epsilon + abs(mainOpposingCosine * shiftedDistanceSquared));

                                        // Power heuristic between light sample from base, BSDF sample from base, light sample from offset, BSDF sample from offset.
                                        float shiftedWeightDenominator = (jacobian * shiftedRays[i].pdf) * (jacobian * shiftedRays[i].pdf) * ((shiftedDRecPdf * shiftedDRecPdf) + (shiftedBsdfPdf * shiftedBsdfPdf));
                                        weight = mainWeightNumerator / (D_EPSILON + shiftedWeightDenominator + mainWeightDenominator);

                                        mainContribution = main.throughput * (mainBSDFValue * mainEmitterRadiance);
                                        shiftedContribution = jacobian * shiftedRays[i].throughput * (shiftedBsdfValue * shiftedEmitterRadiance);
                                    }
                                }
                            }
                        }

                        if (!shiftSuccessful) {
                            // The offset path cannot be generated; Set offset PDF and offset throughput to zero. This is what remains.

                            // Power heuristic between light sample from base, BSDF sample from base, light sample from offset, BSDF sample from offset. (Offset path has zero PDF)
                            float shiftedWeightDenominator = 0.0;
                            weight = mainWeightNumerator / (D_EPSILON + mainWeightDenominator);

                            mainContribution = main.throughput * (mainBSDFValue * mainEmitterRadiance);
                            shiftedContribution = float3(0, 0, 0);
                        }

                        // Note: Using also the offset paths for the throughput estimate, like we do here, provides some advantage when a large reconstruction alpha is used,
                        // but using only throughputs of the base paths doesn't usually lose by much.

#ifndef CENTRAL_RADIANCE
                        addRadiance(main, mainContribution, weight);
                        addRadiance(shiftedRays[i], shiftedContribution, weight);
#endif
                        addGradient(shiftedRays[i], shiftedContribution - mainContribution, weight);
                    } // for(int i = 0; i < secondaryCount; i++)
                } // Strict normals
            }
        } // Sample incoming radiance from lights.

        /* ==================================================================== */
        /*               BSDF sampling and emitter hits                         */
        /* ==================================================================== */

        // Sample a new direction from BSDF * cos(theta).
        BSDFSampleResult mainBsdfResult = sampleBSDF(main);

        if (mainBsdfResult.pdf <= 0.0) {
            // Impossible base path.
            // e.g., can happen when there is no valid material
            break;
        }

        const Vector mainWo = toWorld(main.rRec.its, mainBsdfResult.bRec.wo);

        // Prevent light leaks due to the use of shading normals.
        if (m_strictNormals && dot(Frame_n(main.rRec.its.geoFrame), mainWo) * Frame_cosTheta(mainBsdfResult.bRec.wo) <= 0) {
            break;
        }

        // The old intersection structure is still needed after main.rRec.its gets updated.
        Intersection previousMainIts = main.rRec.its;

        // Trace a ray in the sampled direction.
        bool mainHitEmitter = false;
        Spectrum mainEmitterRadiance = float3(0, 0, 0);

        DirectSamplingRecord mainDRec = createDirectSamplingRecord(main.rRec.its);
        BSDF mainBSDF = getBSDF(main.rRec.its, main.ray);

        // Update the vertex types.
        VertexType mainVertexType = getVertexType(main, mainBsdfResult.bRec.sampledType);
        VertexType mainNextVertexType;

        main.ray.o = main.rRec.its.p;
		main.ray.d = mainWo;
		main.ray.time = main.ray.time;

        if (rayIntersect(main.ray, main.rRec.its)) {
            // Intersected something - check if it was a luminaire.
            if (main.rRec.its.isEmitter) {
                mainEmitterRadiance = Le(main.rRec.its, -main.ray.d);

                // mainDRec.setQuery(main.ray, main.rRec.its); is equal to the following:
                mainDRec.p = main.rRec.its.p;
                mainDRec.n = Frame_n(main.rRec.its.shFrame);
                mainDRec.measure = ESolidAngle;// not specified -> default value
                // mainDRec.uv = main.rRec.its.uv; // is this being used anywhere? not that I'd know of
                mainDRec.d = main.ray.d;
                mainDRec.dist = main.rRec.its.t;

                mainHitEmitter = true;
            }

            // Update the vertex type.
            mainNextVertexType = getVertexType(main, mainBsdfResult.bRec.sampledType);
        } else {
            // Intersected nothing -- perhaps there is an environment map?
            // Hit the environment map.
            mainEmitterRadiance = evalEnvironment(main.ray);
            if (!fillDirectSamplingRecord(mainDRec, main.ray))
                break;
            mainHitEmitter = true;

            // Handle environment connection as diffuse (that's ~infinitely far away).
            // Update the vertex type.
            mainNextVertexType = VERTEX_TYPE_DIFFUSE;

        }

        // Continue the shift.
        float mainBsdfPdf = mainBsdfResult.pdf;
        float mainPreviousPdf = main.pdf;

        if(main.rRec.depth > 1) {
            // first time is ignored ->
            // instead of color, we are computing global illumination
            main.throughput *= mainBsdfResult.weight * mainBsdfResult.pdf;
            main.pdf *= mainBsdfResult.pdf;
        }
        // index of refraction for this ray
        main.eta *= mainBsdfResult.bRec.eta;

        // Compute the probability density of generating base path's direction using the implemented direct illumination sampling technique.
        const float mainLumPdf = (mainHitEmitter && main.rRec.depth + 1 >= m_minDepth && !(mainBsdfResult.bRec.sampledType & EDelta)) ?
            pdfEmitterDirect(mainDRec) : 0.0;

        // Power heuristic weights for the following strategies: light sample from base, BSDF sample from base.
        float mainWeightNumerator = mainPreviousPdf * mainBsdfResult.pdf;
        float mainWeightDenominator = (mainPreviousPdf * mainPreviousPdf) * ((mainLumPdf * mainLumPdf) + (mainBsdfPdf * mainBsdfPdf));

#ifdef CENTRAL_RADIANCE
        if (main.rRec.depth + 1 >= m_minDepth) {
            addRadiance(main, main.throughput * mainEmitterRadiance, mainWeightNumerator / (D_EPSILON + mainWeightDenominator));
        }
#endif

        // Construct the offset paths and evaluate emitter hits.
        for (int i = 0; i < secondaryCount; i++) {

            // Spectrum shiftedEmitterRadiance = 0.0;
            Spectrum mainContribution = 0.0;
            Spectrum shiftedContribution = 0.0;
            float weight = 0;

            bool postponedShiftEnd = false; // Kills the shift after evaluating the current radiance.

            if (shiftedRays[i].alive) {
                // The offset path is still good, so it makes sense to continue its construction.
                float shiftedPreviousPdf = shiftedRays[i].pdf;

                if (shiftedRays[i].connection_status == RAY_CONNECTED) {
                    // The offset path keeps following the base path.
                    // As all relevant vertices are shared, we can just reuse the sampled values.
                    Spectrum shiftedBsdfValue = mainBsdfResult.weight * mainBsdfResult.pdf;
                    float shiftedBsdfPdf = mainBsdfPdf;
                    float shiftedLumPdf = mainLumPdf;
                    Spectrum shiftedEmitterRadiance = mainEmitterRadiance;

                    // Update throughput and pdf.
                    if(main.rRec.depth > 1){
                        shiftedRays[i].throughput *= shiftedBsdfValue;
                        shiftedRays[i].pdf *= shiftedBsdfPdf;
                    }

                    // Power heuristic between light sample from base, BSDF sample from base, light sample from offset, BSDF sample from offset.
                    float shiftedWeightDenominator = (shiftedPreviousPdf * shiftedPreviousPdf) * ((shiftedLumPdf * shiftedLumPdf) + (shiftedBsdfPdf * shiftedBsdfPdf));
                    weight = mainWeightNumerator / (D_EPSILON + shiftedWeightDenominator + mainWeightDenominator);

                    mainContribution = main.throughput * mainEmitterRadiance;
                    shiftedContribution = shiftedRays[i].throughput * shiftedEmitterRadiance; // Note: Jacobian baked into .throughput.
                } else if (shiftedRays[i].connection_status == RAY_RECENTLY_CONNECTED) {
                    // Recently connected - follow the base path but evaluate BSDF to the new direction.
                    Vector3 incomingDirection = normalize(shiftedRays[i].rRec.its.p - main.ray.o);
                    BSDFSamplingRecord bRec;
					bRec.its = previousMainIts;
					bRec.wi = toLocal(previousMainIts, incomingDirection);
					bRec.wo = toLocal(previousMainIts, main.ray.d);
					bRec.mode = ETransportRadiance;

                    // Note: mainBSDF is the BSDF at previousMainIts, which is the current position of the offset path.

                    EMeasure measure = ESolidAngle;
                    if((mainBsdfResult.bRec.sampledType & EDelta) != 0)
                        measure = EDiscrete;

                    Spectrum shiftedBsdfValue = eval(mainBSDF, bRec, measure);
                    float shiftedBsdfPdf = pdf(mainBSDF, bRec, measure);

                    float shiftedLumPdf = mainLumPdf;
                    Spectrum shiftedEmitterRadiance = mainEmitterRadiance;

                    // Update throughput and pdf.
                    if(main.rRec.depth > 1){
                        shiftedRays[i].throughput *= shiftedBsdfValue;
                        shiftedRays[i].pdf *= shiftedBsdfPdf;
                    }

                    shiftedRays[i].connection_status = RAY_CONNECTED;

                    // Power heuristic between light sample from base, BSDF sample from base, light sample from offset, BSDF sample from offset.
                    float shiftedWeightDenominator = (shiftedPreviousPdf * shiftedPreviousPdf) * ((shiftedLumPdf * shiftedLumPdf) + (shiftedBsdfPdf * shiftedBsdfPdf));
                    weight = mainWeightNumerator / (D_EPSILON + shiftedWeightDenominator + mainWeightDenominator);

                    mainContribution = main.throughput * mainEmitterRadiance;
                    shiftedContribution = shiftedRays[i].throughput * shiftedEmitterRadiance; // Note: Jacobian baked into .throughput.
                } else {

                    // Not connected - apply either reconnection or half-vector duplication shift.
                    BSDF shiftedBSDF = getBSDF(shiftedRays[i].rRec.its, shiftedRays[i].ray);

                    // Update the vertex type of the offset path.
                    VertexType shiftedVertexType = getVertexType(shiftedRays[i], mainBsdfResult.bRec.sampledType);

                    if (mainVertexType == VERTEX_TYPE_DIFFUSE && mainNextVertexType == VERTEX_TYPE_DIFFUSE && shiftedVertexType == VERTEX_TYPE_DIFFUSE) {
                        // Use reconnection shift.

                        // Optimization: Skip the last raycast and BSDF evaluation for the offset path when it won't contribute and isn't needed anymore.
                        if (!lastSegment || mainHitEmitter) {
                            ReconnectionShiftResult shiftResult;
                            bool environmentConnection = false;

                            if (main.rRec.its.isValid) {
                                // This is an actual reconnection shift.
                                shiftResult = reconnectShift(main.ray.o, main.rRec.its.p, shiftedRays[i].rRec.its.p, Frame_n(main.rRec.its.geoFrame), main.ray.time);
                            } else {
                                // This is a reconnection at infinity in environment direction.
                                environmentConnection = true;
                                shiftResult = environmentShift(main.ray, shiftedRays[i].rRec.its.p);
                            }

                            // bool shift_failed;
                            if (!shiftResult.success) {
                                // Failed to construct the offset path.
                                shiftedRays[i].alive = false;
                                // shift_failed = true;
                            } else {
                                Vector3 incomingDirection = -shiftedRays[i].ray.d;
                                Vector3 outgoingDirection = shiftResult.wo;

                                BSDFSamplingRecord bRec;
                                bRec.its = shiftedRays[i].rRec.its;
                                bRec.wi = toLocal(shiftedRays[i].rRec.its, incomingDirection);
                                bRec.wo = toLocal(shiftedRays[i].rRec.its, outgoingDirection);
                                bRec.mode = ETransportRadiance;

                                // Strict normals check.
                                if (m_strictNormals && dot(outgoingDirection, Frame_n(shiftedRays[i].rRec.its.geoFrame)) * Frame_cosTheta(bRec.wo) <= 0) {
                                    shiftedRays[i].alive = false;
                                    // shift_failed = true;
                                } else {
                                    // Evaluate the BRDF to the new direction.
                                    Spectrum shiftedBsdfValue = eval(shiftedBSDF, bRec);
                                    float shiftedBsdfPdf = pdf(shiftedBSDF, bRec);

                                    // Update throughput and pdf.
                                    if(main.rRec.depth > 1){
                                        shiftedRays[i].throughput *= shiftedBsdfValue * shiftResult.jacobian;
                                        shiftedRays[i].pdf *= shiftedBsdfPdf * shiftResult.jacobian;
                                    }

                                    shiftedRays[i].connection_status = RAY_RECENTLY_CONNECTED;

                                    if (mainHitEmitter) {
                                        // Also the offset path hit the emitter, as visibility was checked at reconnectShift or environmentShift.

                                        // Evaluate radiance to this direction.
                                        Spectrum shiftedEmitterRadiance = 0.0;
                                        float shiftedLumPdf = 0.0;

                                        if (main.rRec.its.isValid) {
                                            // Hit an object.
                                            if (mainHitEmitter) {
                                                shiftedEmitterRadiance = Le(main.rRec.its, -outgoingDirection);

                                                // Evaluate the light sampling PDF of the new segment.
                                                DirectSamplingRecord shiftedDRec = mainDRec;
                                                shiftedDRec.p = mainDRec.p;
                                                shiftedDRec.n = mainDRec.n;
                                                shiftedDRec.dist = length(mainDRec.p - shiftedRays[i].rRec.its.p);
                                                shiftedDRec.d = (mainDRec.p - shiftedRays[i].rRec.its.p) / shiftedDRec.dist;
                                                shiftedDRec.ref = mainDRec.ref;
                                                shiftedDRec.refN = Frame_n(shiftedRays[i].rRec.its.shFrame);
                                                // shiftedDRec.object = mainDRec.object;

                                                shiftedLumPdf = pdfEmitterDirect(shiftedDRec);
                                            }
                                        } else {
                                            // Hit the environment.
                                            shiftedEmitterRadiance = mainEmitterRadiance;
                                            shiftedLumPdf = mainLumPdf;
                                        }

                                        // Power heuristic between light sample from base, BSDF sample from base, light sample from offset, BSDF sample from offset.
                                        float shiftedWeightDenominator = (shiftedPreviousPdf * shiftedPreviousPdf) * ((shiftedLumPdf * shiftedLumPdf) + (shiftedBsdfPdf * shiftedBsdfPdf));
                                        weight = mainWeightNumerator / (D_EPSILON + shiftedWeightDenominator + mainWeightDenominator);

                                        mainContribution = main.throughput * mainEmitterRadiance;
                                        shiftedContribution = shiftedRays[i].throughput * shiftedEmitterRadiance; // Note: Jacobian baked into .throughput.
                                    }
                                }
                            }
                        }
                    } else {

                        bool half_vector_shift_failed = false;

                        // Use half-vector duplication shift. These paths could not have been sampled by light sampling (by our decision).
                        Vector3 tangentSpaceIncomingDirection = toLocal(shiftedRays[i].rRec.its, -shiftedRays[i].ray.d);
                        Vector3 tangentSpaceOutgoingDirection;
                        Spectrum shiftedEmitterRadiance = 0.0;

                        BSDF shiftedBSDF = getBSDF(shiftedRays[i].rRec.its, shiftedRays[i].ray);

                        // Deny shifts between Dirac and non-Dirac BSDFs.
                        bool bothDelta = (mainBsdfResult.bRec.sampledType & EDelta) && (shiftedBSDF.type & EDelta);
                        bool bothSmooth = (mainBsdfResult.bRec.sampledType & ESmooth) && (shiftedBSDF.type & ESmooth);
                        if (!(bothDelta || bothSmooth)) {
                            shiftedRays[i].alive = false;
                            half_vector_shift_failed = true;
                        }

                        // SAssert(abs(lengthSquared(shiftedRays[i].ray.d) - 1) < 0.000001);

                        // Apply the local shift.
                        if (!half_vector_shift_failed) {

                            HalfVectorShiftResult shiftResult = halfVectorShift(mainBsdfResult.bRec.wi, mainBsdfResult.bRec.wo, toLocal(shiftedRays[i].rRec.its, -shiftedRays[i].ray.d), mainBSDF.eta, shiftedBSDF.eta);
                            if (mainBsdfResult.bRec.sampledType & EDelta) {
                                // Dirac delta integral is a point evaluation - no Jacobian determinant!
                                shiftResult.jacobian = 1.0;
                            }

                            if (shiftResult.success) {
                                // Invertible shift, success.
                                if(main.rRec.depth > 1){// color -> gi
                                    shiftedRays[i].throughput *= shiftResult.jacobian;
                                    shiftedRays[i].pdf *= shiftResult.jacobian;
                                }
                                tangentSpaceOutgoingDirection = shiftResult.wo;
                            } else {
                                // The shift is non-invertible so kill it.
                                shiftedRays[i].alive = false;
                                half_vector_shift_failed = true;
                            }

                            if (!half_vector_shift_failed) {

                                Vector3 outgoingDirection = toWorld(shiftedRays[i].rRec.its, tangentSpaceOutgoingDirection);

                                // Update throughput and pdf.
                                BSDFSamplingRecord bRec;
								bRec.its = shiftedRays[i].rRec.its;
								bRec.wi = tangentSpaceIncomingDirection;
								bRec.wo = tangentSpaceOutgoingDirection;
								bRec.mode = ETransportRadiance;

                                EMeasure measure = ESolidAngle;
                                if((mainBsdfResult.bRec.sampledType & EDelta) != 0)
                                    measure = EDiscrete;

                                if(main.rRec.depth > 1){
                                    shiftedRays[i].throughput *= eval(shiftedBSDF, bRec, measure);
                                    shiftedRays[i].pdf *= pdf(shiftedBSDF, bRec, measure);
                                }

                                if (shiftedRays[i].pdf == 0.0) {
                                    // Offset path is invalid!
                                    shiftedRays[i].alive = false;
                                    half_vector_shift_failed = true;
                                }

                                // Strict normals check to produce the same results as bidirectional methods when normal mapping is used.
                                if (!half_vector_shift_failed && m_strictNormals && dot(outgoingDirection, Frame_n(shiftedRays[i].rRec.its.geoFrame)) * Frame_cosTheta(bRec.wo) <= 0) {
                                    shiftedRays[i].alive = false;
                                    half_vector_shift_failed = true;
                                }

                                if (!half_vector_shift_failed) {
                                    // Update the vertex type.
                                    VertexType shiftedVertexType = getVertexType(shiftedRays[i], mainBsdfResult.bRec.sampledType);

                                    // Trace the next hit point.
                                    shiftedRays[i].ray.o = shiftedRays[i].rRec.its.p;
									shiftedRays[i].ray.d = outgoingDirection;
									shiftedRays[i].ray.time = main.ray.time;

                                    if (!rayIntersect(shiftedRays[i].ray, shiftedRays[i].rRec.its)) {
                                        // Hit nothing - Evaluate environment radiance.
                                        /*if(!env) {
                                        // Since base paths that hit nothing are not shiftedRays[i], we must be symmetric and kill shifts that hit nothing.
                                        shiftedRays[i].alive = false;
                                        goto half_vector_shift_failed;
                                        }*/
                                        if (main.rRec.its.isValid) {
                                            // Deny shifts between env and non-env.
                                            shiftedRays[i].alive = false;
                                            half_vector_shift_failed = true;
                                        }

                                        if (mainVertexType == VERTEX_TYPE_DIFFUSE && shiftedVertexType == VERTEX_TYPE_DIFFUSE) {
                                            // Environment reconnection shift would have been used for the reverse direction!
                                            shiftedRays[i].alive = false;
                                            half_vector_shift_failed = true;
                                        }

                                        if (!half_vector_shift_failed) {
                                            // The offset path is no longer valid after this path segment.
                                            shiftedEmitterRadiance = evalEnvironment(shiftedRays[i].ray);
                                            postponedShiftEnd = true;
                                        }
                                    } else {
                                        // Hit something.
                                        if (!main.rRec.its.isValid) {
                                            // Deny shifts between env and non-env.
                                            shiftedRays[i].alive = false;
                                            half_vector_shift_failed = true;
                                        } else {
                                            VertexType shiftedNextVertexType = getVertexType(shiftedRays[i], mainBsdfResult.bRec.sampledType);

                                            // Make sure that the reverse shift would use this same strategy!
                                            // ==============================================================

                                            if (mainVertexType == VERTEX_TYPE_DIFFUSE && shiftedVertexType == VERTEX_TYPE_DIFFUSE && shiftedNextVertexType == VERTEX_TYPE_DIFFUSE) {
                                                // Non-invertible shift: the reverse-shift would use another strategy!
                                                shiftedRays[i].alive = false;
                                                half_vector_shift_failed = true;
                                            } else if (shiftedRays[i].rRec.its.isEmitter) {
                                                // Hit emitter.
                                                shiftedEmitterRadiance = Le(shiftedRays[i].rRec.its, -shiftedRays[i].ray.d);
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // half_vector_shift_failed:
                        if (shiftedRays[i].alive) {
                            // Evaluate radiance difference using power heuristic between BSDF samples from base and offset paths.
                            // Note: No MIS with light sampling since we don't use it for this connection type.
                            weight = main.pdf / (shiftedRays[i].pdf * shiftedRays[i].pdf + main.pdf * main.pdf);
                            mainContribution = main.throughput * mainEmitterRadiance;
                            shiftedContribution = shiftedRays[i].throughput * shiftedEmitterRadiance; // Note: Jacobian baked into .throughput.
                        } else {
                            // Handle the failure without taking MIS with light sampling, as we decided not to use it in the half-vector-duplication case.
                            // Could have used it, but so far there has been no need. It doesn't seem to be very useful.
                            weight = 1.0 / main.pdf;
                            mainContribution = main.throughput * mainEmitterRadiance;
                            shiftedContribution = 0;

                            // Disable the failure detection below since the failure was already handled.
                            shiftedRays[i].alive = true;
                            postponedShiftEnd = true;

                        }
                    }
                }
            }

            // shift_failed:
            if (!shiftedRays[i].alive) {
                // The offset path cannot be generated; Set offset PDF and offset throughput to zero.
                weight = mainWeightNumerator / (D_EPSILON + mainWeightDenominator);
                mainContribution = main.throughput * mainEmitterRadiance;
                shiftedContribution = 0;
            }

            // Note: Using also the offset paths for the throughput estimate, like we do here, provides some advantage when a large reconstruction alpha is used,
            // but using only throughputs of the base paths doesn't usually lose by much.
            if (main.rRec.depth + 1 >= m_minDepth) {
#ifndef CENTRAL_RADIANCE
                addRadiance(main, mainContribution, weight);
                addRadiance(shiftedRays[i], shiftedContribution, weight);
#endif
                addGradient(shiftedRays[i], shiftedContribution - mainContribution, weight);
            }

            if (postponedShiftEnd) {
                shiftedRays[i].alive = false;
            }
        }

        // Stop if the base path hit the environment.
        main.rRec.type = ERadianceNoEmission;
        // second branch is uncommented, because it is always false
        if (!main.rRec.its.isValid/* || !(main.rRec.type & EIndirectSurfaceRadiance)*/) {
            break;
        }

        if (main.rRec.depth++ >= m_rrDepth) {
            /* Russian roulette: try to keep path weights equal to one,
            while accounting for the solid angle compression at refractive
            index boundaries. Stop with at least some probability to avoid
            getting stuck (e.g. due to total internal reflection) */

            float q = min(max3(main.throughput / main.pdf) * main.eta * main.eta, (float)0.95f);
            if (nextSample1D(main.rRec) >= q)
                break;

            main.pdf *= q;
            for (int i = 0; i < secondaryCount; i++) {
                shiftedRays[i].pdf *= q;
            }
        }
    }

    return true;

}

[shader("miss")]
void SurfelPTMiss(inout RayPayload rayPayload: SV_RayPayload) {
    rayPayload.distance = _Far;
    rayPayload.bsdf.numComponents = 0;
}


#endif // GPT_CGINC