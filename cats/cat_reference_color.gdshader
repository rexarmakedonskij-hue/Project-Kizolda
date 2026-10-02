shader_type spatial;

const vec3 COAT = vec3(0.584, 0.521, 0.451);
const vec3 LIGHT_FUR = vec3(0.784, 0.730, 0.651);
const vec3 POINT = vec3(0.168, 0.135, 0.122);

varying vec3 fur_color;

vec3 bone_color(uint bone, vec3 position) {
	if (bone == 4u) {
		return position.x > 0.00265 && position.z < 0.00195 ? LIGHT_FUR : POINT;
	}
	if ((bone >= 3u && bone <= 6u) || (bone >= 19u && bone <= 22u)) {
		return POINT;
	}
	if (bone == 2u || bone == 10u || bone == 14u || bone == 18u || bone == 26u) {
		return LIGHT_FUR;
	}
	return COAT;
}

void vertex() {
	float total = dot(BONE_WEIGHTS, vec4(1.0));
	vec3 weighted = bone_color(BONE_INDICES.x, VERTEX) * BONE_WEIGHTS.x;
	weighted += bone_color(BONE_INDICES.y, VERTEX) * BONE_WEIGHTS.y;
	weighted += bone_color(BONE_INDICES.z, VERTEX) * BONE_WEIGHTS.z;
	weighted += bone_color(BONE_INDICES.w, VERTEX) * BONE_WEIGHTS.w;
	fur_color = total > 0.0 ? weighted / total : COAT;
	if (VERTEX.x > 0.00138 && VERTEX.z > 0.00140) {
		fur_color = VERTEX.x > 0.00265 && VERTEX.z < 0.00195 ? LIGHT_FUR : POINT;
	} else if (VERTEX.x < -0.00140 && VERTEX.z > 0.00140) {
		fur_color = POINT;
	} else if (VERTEX.z < 0.00020) {
		fur_color = LIGHT_FUR;
	}
}

void fragment() {
	ALBEDO = fur_color;
	ROUGHNESS = 0.86;
}
