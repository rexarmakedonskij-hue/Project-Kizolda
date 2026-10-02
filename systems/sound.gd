extends Node
var clips := {}

func _ready() -> void:
	for kind in ["work", "cat", "spray", "scratch", "win", "keyboard", "cup", "spill", "purr"]:
		var bytes := PackedByteArray()
		var duration := 1.4 if kind == "purr" else (0.12 if kind == "work" else 0.35)
		var count := int(22050 * duration)
		bytes.resize(count * 2)
		for i in range(count):
			var t := float(i) / 22050.0
			var frequency := 720.0 if kind == "work" else 460.0
			if kind == "win": frequency = 660.0 + floorf(t * 9.0) * 110.0
			if kind == "keyboard": frequency = 160.0 + 60.0 * sin(t * 90)
			if kind == "cup": frequency = 1600.0
			var value := sin(TAU * frequency * t + (8.0 * sin(t * 14.0) if kind == "cat" else 0.0))
			if kind in ["spray", "scratch"]: value = randf_range(-1, 1) * 0.5
			if kind == "spill": value = randf_range(-1,1) * .5 + sin(t*TAU*90)*.3
			if kind == "cup": value *= exp(-t*12)
			if kind == "purr": value = (sin(TAU * 90 * t) + .3 * sin(TAU * 180 * t)) * (.4 + .6 * pow(sin(TAU * 25 * t), 2)) * .45
			value *= sin(PI * float(i) / count) * 0.22
			bytes.encode_s16(i * 2, int(value * 32767))
		var clip := AudioStreamWAV.new()
		clip.format = AudioStreamWAV.FORMAT_16_BITS
		clip.mix_rate = 22050
		clip.data = bytes
		clips[kind] = clip

func play(kind: String) -> void:
	var voice := AudioStreamPlayer.new()
	voice.stream = clips[kind]
	voice.volume_db = -5
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()

func play_at(kind: String, position: Vector3) -> void:
	var voice := AudioStreamPlayer3D.new()
	voice.stream = clips[kind]
	voice.volume_db = -3
	voice.unit_size = 4
	voice.max_distance = 20
	add_child(voice)
	voice.global_position = position
	voice.finished.connect(voice.queue_free)
	voice.play()

func _exit_tree() -> void:
	for voice in get_children():
		voice.stop()
		voice.stream = null
