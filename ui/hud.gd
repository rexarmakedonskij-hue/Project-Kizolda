extends CanvasLayer
var quota_label: Label
var damage_label: Label
var clock_label: Label
var status_label: Label
func _ready() -> void:
	var panel := ColorRect.new(); panel.color = Color(0.08,0.11,0.16,0.84); panel.position = Vector2(20,20); panel.size = Vector2(360,165); add_child(panel)
	quota_label = _label(Vector2(38,35),22)
	damage_label = _label(Vector2(38,68),22)
	clock_label = _label(Vector2(38,101),20)
	var hint := _label(Vector2(38,137),16); hint.text = "[F] работать   [Пробел] прогнать кота"
	status_label = _label(Vector2(20,650),20); status_label.size = Vector2(1100,40)
func update_values(quota: int, damage: float, time: float) -> void:
	quota_label.text = "Квота: %d%% / 100%%" % quota
	damage_label.text = "Обои: %.0f%% / 50%%" % damage
	clock_label.text = "Смена: %02d:%02d" % [int(time)/60, int(time)%60]
func show_status(message: String) -> void: status_label.text = message
func _label(pos: Vector2, font_size: int) -> Label:
	var label := Label.new(); label.position = pos; label.add_theme_font_size_override("font_size",font_size); label.add_theme_color_override("font_color",Color.WHITE); add_child(label); return label
