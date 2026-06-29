class_name MainMenu
extends Control

signal play_single(ai_count)
signal play_hotseat(player_count)
signal play_online()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.34, 0.62, 0.86)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.offset_left = -200
	center.offset_right = 200
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 16)
	add_child(center)

	var title := Label.new()
	title.text = "FARMRUSH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(1, 0.95, 0.7))
	title.add_theme_color_override("font_outline_color", Color(0.3, 0.2, 0.05))
	title.add_theme_constant_override("outline_size", 8)
	center.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Build. Trade. Settle the valley."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_color_override("font_color", Color.WHITE)
	center.add_child(subtitle)

	center.add_child(_spacer(16))

	# Single player + AI count.
	var ai_row := HBoxContainer.new()
	ai_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ai_row.add_child(_text("Opponents:"))
	var ai_spin := SpinBox.new()
	ai_spin.min_value = 1
	ai_spin.max_value = 5
	ai_spin.value = 2
	ai_row.add_child(ai_spin)
	center.add_child(ai_row)
	center.add_child(_big_button("🤖  Single Player", func(): play_single.emit(int(ai_spin.value))))

	# Hotseat + player count.
	var hs_row := HBoxContainer.new()
	hs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	hs_row.add_child(_text("Players:"))
	var hs_spin := SpinBox.new()
	hs_spin.min_value = 2
	hs_spin.max_value = 6
	hs_spin.value = 2
	hs_row.add_child(hs_spin)
	center.add_child(hs_row)
	center.add_child(_big_button("🛋  Local Hotseat", func(): play_hotseat.emit(int(hs_spin.value))))

	center.add_child(_big_button("🌐  Online Multiplayer", func(): play_online.emit()))
	center.add_child(_big_button("🚪  Quit", func(): get_tree().quit()))

func _big_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(320, 52)
	b.add_theme_font_size_override("font_size", 22)
	b.pressed.connect(cb)
	return b

func _text(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_color_override("font_color", Color.WHITE)
	return l

func _spacer(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c
