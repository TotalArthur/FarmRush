class_name UITheme
extends RefCounted

## Shared styling: warm ivory panels with hairline borders and soft shadows,
## one terracotta primary action color, and quiet bordered secondary buttons.
## Pure helpers — no state — used by both the menu and the in-game HUD.

# Palette (warm neutrals + terracotta) --------------------------------------
const BG_DEEP := Color("262624")        # page background (warm charcoal)
const BG_SIDEBAR := Color("1f1e1d")
const PANEL := Color("faf9f5")          # warm ivory panel
const PANEL_SOFT := Color("f0eee6")
const INK := Color("2a2a26")            # warm near-black text
const INK_SOFT := Color("7a786e")
const ACCENT := Color("cc6b49")         # terracotta (primary action)
const GREEN := Color("4d9e63")
const BLUE := Color("5478b8")
const RED := Color("c14e3f")
const SLATE := Color("83827a")
const HAIRLINE := Color("d9d6ca")       # panel/button border tone

# In-game HUD skin: dark navy glass so panels pop against the bright ocean
# without stealing attention from the board.
const HUD_BG := Color(0.086, 0.129, 0.180, 0.93)        # deep navy @ 93%
const HUD_BG_SOFT := Color(0.128, 0.183, 0.245, 0.95)   # row / inset tone
const HUD_TEXT := Color("f2f5f8")
const HUD_TEXT_SOFT := Color("9db0c2")
const HUD_LINE := Color(1, 1, 1, 0.10)                  # hairline on dark

# Vibrant, instantly distinguishable resource colors (inventory/cards/costs).
const RES_VIVID := {
	Consts.Res.WOOD: Color("2f9e4f"),   # lumber green
	Consts.Res.BRICK: Color("e2603c"),  # brick orange-red
	Consts.Res.SHEEP: Color("8bd34e"),  # wool lime
	Consts.Res.WHEAT: Color("f5b81f"),  # grain gold
	Consts.Res.ORE: Color("8296ab"),    # ore steel blue
}

# Resource accent colors (match the board).
static func res_color(res: int) -> Color:
	return Consts.RES_COLOR[res]

# Panels -------------------------------------------------------------------
static func card_style(bg: Color = PANEL, radius: int = 12) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.14)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 4)
	sb.set_border_width_all(1)
	sb.border_color = HAIRLINE
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb

static func make_panel(bg: Color = PANEL, radius: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", card_style(bg, radius))
	return p

## Dark glass HUD panel — high contrast against the bright 3D ocean, with a
## deeper drop shadow so it visually floats above the board.
static func hud_panel(radius: int = 12) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = HUD_BG
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = HUD_LINE
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 9
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	p.add_theme_stylebox_override("panel", sb)
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

## Quiet secondary button: ivory face, ink text, hairline border. Use for
## everything that isn't the single primary action on screen.
static func secondary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_stylebox_override("normal", _sec_box(PANEL))
	b.add_theme_stylebox_override("hover", _sec_box(Color("f1efe7")))
	b.add_theme_stylebox_override("pressed", _sec_box(Color("e7e4d8")))
	b.add_theme_stylebox_override("disabled", _sec_box(Color(PANEL.r, PANEL.g, PANEL.b, 0.5)))
	b.add_theme_stylebox_override("focus", _sec_box(Color("f1efe7")))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", INK)
	b.add_theme_color_override("font_disabled_color", Color(INK_SOFT.r, INK_SOFT.g, INK_SOFT.b, 0.6))
	b.add_theme_font_size_override("font_size", 16)
	add_button_juice(b)
	return b

static func _sec_box(bg: Color, radius: int = 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	sb.set_border_width_all(1)
	sb.border_color = HAIRLINE
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0, 0, 0, 0.10)
	sb.shadow_size = 2
	sb.shadow_offset = Vector2(0, 1)
	return sb

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

# Cost-aware build button --------------------------------------------------
## A secondary button whose face shows the action name over its exact
## resource cost (icon + amount per resource). Pair with update_cost_button()
## every refresh: unaffordable rows tint red and the whole button fades.
static func cost_button(text: String, cost: Dictionary) -> Button:
	var b := secondary_button("")
	b.custom_minimum_size = Vector2(124, 58)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var name_l := Label.new()
	name_l.text = text
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", INK)
	v.add_child(name_l)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 5)
	v.add_child(row)
	var nodes: Array = []
	for r in Consts.RES_ALL:
		if not cost.has(r) or cost[r] <= 0:
			continue
		var icon := resource_icon(r, 14)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var n := Label.new()
		n.text = str(cost[r])
		n.add_theme_font_size_override("font_size", 12)
		n.add_theme_color_override("font_color", INK_SOFT)
		row.add_child(n)
		nodes.append({ "res": r, "need": cost[r], "icon": icon, "lbl": n })
	b.set_meta("cost_nodes", nodes)
	return b

## Refresh a cost_button against the player's exact inventory: rows the
## player can't cover tint red, and the caller-set disabled state fades the
## whole button so unaffordable actions visibly recede.
static func update_cost_button(b: Button, have: Dictionary) -> void:
	for e in b.get_meta("cost_nodes", []):
		var enough: bool = have.get(e["res"], 0) >= e["need"]
		e["icon"].modulate = Color(1, 1, 1) if enough else Color(1, 0.42, 0.42)
		e["lbl"].add_theme_color_override("font_color", INK_SOFT if enough else Color("c0392b"))
	b.modulate.a = 0.55 if b.disabled else 1.0

# Hand card (a real card prop: colored face, icon chip, count) -------------
static func hand_card(res: int, count: int) -> Control:
	var col: Color = RES_VIVID[res]
	var card := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = col.darkened(0.35)
	sb.shadow_color = Color(0, 0, 0, 0.32)
	sb.shadow_size = 6
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 9
	sb.content_margin_bottom = 7
	card.add_theme_stylebox_override("panel", sb)
	card.custom_minimum_size = Vector2(64, 90)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 5)
	card.add_child(v)
	# Ivory inner chip carrying the resource icon.
	var chip := PanelContainer.new()
	var cb := StyleBoxFlat.new()
	cb.bg_color = Color(1, 1, 1, 0.88)
	cb.set_corner_radius_all(9)
	cb.content_margin_left = 5
	cb.content_margin_right = 5
	cb.content_margin_top = 5
	cb.content_margin_bottom = 5
	chip.add_theme_stylebox_override("panel", cb)
	chip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	chip.add_child(resource_icon(res, 30))
	v.add_child(chip)
	var num := Label.new()
	num.text = str(count)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.add_theme_font_size_override("font_size", 26)
	num.add_theme_color_override("font_color", Color.WHITE)
	num.add_theme_color_override("font_outline_color", col.darkened(0.55))
	num.add_theme_constant_override("outline_size", 5)
	v.add_child(num)
	if count == 0:
		card.modulate = Color(0.9, 0.9, 0.9, 0.6)
	add_button_juice(card)
	return card

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
