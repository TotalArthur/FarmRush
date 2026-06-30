class_name UITheme
extends RefCounted

## Shared modern "browser game" styling (colonist.io-ish): rounded white panels
## with soft drop shadows, chunky colored buttons, and resource chips.
## Pure helpers — no state — used by both the menu and the in-game HUD.

# Palette ------------------------------------------------------------------
const BG_DEEP := Color("0f2a4a")        # page background (deep ocean blue)
const BG_SIDEBAR := Color("13325c")
const PANEL := Color("f6f8fc")          # near-white panel
const PANEL_SOFT := Color("eef2f8")
const INK := Color("22304a")            # dark text
const INK_SOFT := Color("5a6b86")
const ACCENT := Color("ef7d22")         # orange (primary action)
const GREEN := Color("36b24a")
const BLUE := Color("2f7bd6")
const RED := Color("e0483b")
const SLATE := Color("64748b")

# Resource accent colors (match the board).
static func res_color(res: int) -> Color:
	return Consts.RES_COLOR[res]

# Panels -------------------------------------------------------------------
static func card_style(bg: Color = PANEL, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 7
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

static func make_panel(bg: Color = PANEL, radius: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_style(bg, radius))
	return p

static func flat(bg: Color, radius: int = 8) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

# Buttons ------------------------------------------------------------------
static func style_button(b: Button, base: Color, fg: Color = Color.WHITE, radius: int = 10) -> void:
	b.add_theme_stylebox_override("normal", _btn_box(base, radius))
	b.add_theme_stylebox_override("hover", _btn_box(base.lightened(0.12), radius))
	b.add_theme_stylebox_override("pressed", _btn_box(base.darkened(0.12), radius))
	b.add_theme_stylebox_override("disabled", _btn_box(Color(base.r, base.g, base.b, 0.35), radius))
	b.add_theme_stylebox_override("focus", _btn_box(base.lightened(0.05), radius))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.55))
	b.add_theme_font_size_override("font_size", 16)
	add_button_juice(b)

## Tactile feedback: pop up slightly on hover, compress on press.
## Uses `scale` (cosmetic) so it never disturbs container layout.
static func add_button_juice(b: Control) -> void:
	if b.has_meta("juiced"):
		return
	b.set_meta("juiced", true)
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func(): _scale_to(b, 1.06))
	b.mouse_exited.connect(func(): _scale_to(b, 1.0))
	if b is BaseButton:
		b.button_down.connect(func(): _scale_to(b, 0.93))
		b.button_up.connect(func(): _scale_to(b, 1.06))

static func _scale_to(c: Control, s: float) -> void:
	c.pivot_offset = c.size * 0.5
	if not c.is_inside_tree():
		c.scale = Vector2(s, s)
		return
	var tw := c.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "scale", Vector2(s, s), 0.12)

static func _btn_box(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.18)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	return sb

static func make_button(text: String, base: Color, fg: Color = Color.WHITE) -> Button:
	var b := Button.new()
	b.text = text
	style_button(b, base, fg)
	return b

# Two-letter codes (fallback when an icon texture is missing).
const RES_SHORT := {
	Consts.Res.WOOD: "Wd", Consts.Res.BRICK: "Br", Consts.Res.SHEEP: "Sh",
	Consts.Res.WHEAT: "Wh", Consts.Res.ORE: "Or",
}
const RES_ICON_NAME := {
	Consts.Res.WOOD: "wood", Consts.Res.BRICK: "brick", Consts.Res.SHEEP: "sheep",
	Consts.Res.WHEAT: "wheat", Consts.Res.ORE: "ore",
}

## A resource icon at the given pixel size. Uses res://assets/icons/<name>.svg
## if present; otherwise falls back to a colored rounded swatch with its letter.
## Swap the SVGs for 16x16/24x24 art any time — the layout already reserves the
## slot via custom_minimum_size.
static func resource_icon(res: int, size: int = 24) -> Control:
	var path := "res://assets/icons/%s.svg" % RES_ICON_NAME[res]
	if ResourceLoader.exists(path):
		var tr := TextureRect.new()
		tr.texture = load(path)
		tr.custom_minimum_size = Vector2(size, size)
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		return tr
	# Fallback placeholder swatch.
	var col: Color = Consts.RES_COLOR[res]
	var sw := PanelContainer.new()
	sw.add_theme_stylebox_override("panel", flat(col, 6))
	sw.custom_minimum_size = Vector2(size, size)
	var l := Label.new()
	l.text = RES_SHORT[res]
	l.add_theme_color_override("font_color", col.darkened(0.6))
	l.add_theme_font_size_override("font_size", int(size * 0.55))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sw.add_child(l)
	return sw

# Resource chip (icon + count) --------------------------------------------
static func resource_chip(res: int, count: int, big: bool = false) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(PANEL_SOFT, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.add_child(resource_icon(res, 24 if big else 18))
	var num := Label.new()
	num.text = str(count)
	num.add_theme_color_override("font_color", INK)
	num.add_theme_font_size_override("font_size", 20 if big else 16)
	row.add_child(num)
	p.add_child(row)
	return p

static func heading(text: String, size: int = 16, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
