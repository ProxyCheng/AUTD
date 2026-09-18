shader_type canvas_item;
render_mode blend_add;

// 工作量条"工具加成"闪光叠层:覆盖在填充区上方的加法混合层(blend_add),
// 靠自身亮度做出"发光/闪亮"观感,不依赖 WorldEnvironment/bloom(本项目没有也不加)。
// 叠层节点只在 intensity > 0 时显示,故配方不需要工具、空手、无人值守时零绘制开销。
//
// intensity 由 WorkProgressBar 每帧写入 = clampf(work_efficiency - 1.0, 0.0, 1.0):
// 基准 1.0 无闪光,2.0 满档,更大加成饱和到满档 —— 加成越大,扫光越快越亮、闪粒越多越亮。

uniform float intensity : hint_range(0.0, 1.0) = 0.0;
// 叠层像素尺寸(= 填充区尺寸):用于按尺寸给闪粒分格,也用于圆角遮罩。
uniform vec2 overlay_size = vec2(46.0, 5.0);
// 与 HeadBar._ensure_styles 的 fill 圆角(3px)对齐:叠层是方角矩形,
// 不遮罩会在圆角填充区的四角外溢出一圈加色。
uniform float corner_radius = 3.0;
// 斜向光带扫过一遍的基础周期(秒);加成越大扫得越快。
uniform float sweep_period = 1.6;

// 每格一个稳定的伪随机数:同一格跨帧不变,闪粒才是"明灭"而不是逐帧噪声。
float hash21(vec2 in_p) {
	vec2 p = fract(in_p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// 圆角矩形 SDF:<0 在内部,>0 在外部。
float rounded_rect_sdf(vec2 in_px, vec2 in_size, float in_radius) {
	float r = min(in_radius, min(in_size.x, in_size.y) * 0.5);
	vec2 half_size = in_size * 0.5;
	vec2 d = abs(in_px - half_size) - half_size + vec2(r);
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	vec2 px = UV * overlay_size;
	// 裁进圆角填充区;边界 1.5px 软过渡防锯齿。
	float mask = 1.0 - smoothstep(0.0, 1.5, rounded_rect_sdf(px, overlay_size, corner_radius));

	// 1) 斜向扫光:一条高光带沿 x 循环扫过;斜度让它不与条边平行,更像"扫光"。
	float speed = 1.0 + intensity * 1.5;
	float phase = fract(TIME * speed / max(sweep_period, 0.01));
	float diag = UV.x + UV.y * 0.35;
	float band = 1.0 - smoothstep(0.0, 0.22, abs(diag - mix(-0.35, 1.35, phase)));
	vec3 sheen = vec3(1.0, 0.93, 0.65) * band * (0.30 + 0.55 * intensity);

	// 2) 闪粒:按叠层尺寸分格(短条也至少 1 格高,保证格心落在条内),
	//    每格按自己的相位/频率明灭;加成越高存活格越多、越亮。
	vec2 cell_count = max(vec2(1.0), floor(overlay_size / 9.0));
	vec2 grid = UV * cell_count;
	float rnd = hash21(floor(grid));
	float alive = step(0.75 - 0.35 * intensity, rnd);
	float twinkle = pow(max(0.0, sin(TIME * (6.0 + rnd * 9.0) + rnd * 6.28318)), 12.0);
	float glint_dot = smoothstep(0.45, 0.0, length(fract(grid) - 0.5));
	vec3 glints = vec3(1.0, 0.98, 0.82) * alive * twinkle * glint_dot * (0.45 + 0.85 * intensity);

	// 3) 整体微光:让整条在加成期间持续"发热",而不是只在扫光/闪粒瞬间亮。
	float pulse = 0.55 + 0.45 * sin(TIME * 3.2);
	vec3 glow = vec3(1.0, 0.85, 0.45) * 0.10 * intensity * pulse;

	// blend_add 下最终加色 = rgb × alpha,故用 alpha 承载圆角遮罩。
	COLOR = vec4(sheen + glints + glow, mask);
}
