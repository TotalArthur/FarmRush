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
	b.add_theme_stylebox_override("hover", _btn_box(base.lightened(0.10), radius))
	b.add_theme_stylebox_override("pressed", _btn_box(base.darkened(0.12), radius))
	b.add_theme_stylebox_override("disabled", _btn_box(Color(base.r, base.g, base.b, 0.35), radius))
	b.add_theme_stylebox_override("focus", _btn_box(base.lightened(0.05), radius))
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.55))
	b.add_theme_font_size_override("font_size", 16)

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

# Two-letter codes so Wood and Wheat don't both show "W".
const RES_SHORT := {
	Consts.Res.WOOD: "Wd", Consts.Res.BRICK: "Br", Consts.Res.SHEEP: "Sh",
	Consts.Res.WHEAT: "Wh", Consts.Res.ORE: "Or",
}

# Resource chip (colored rounded pill with a count) ------------------------
static func resource_chip(res: int, count: int, big: bool = false) -> PanelContainer:
	var col: Color = Consts.RES_COLOR[res]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", flat(col.lightened(0.12), 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var name := Label.new()
	name.text = RES_SHORT[res]
	name.add_theme_color_override("font_color", col.darkened(0.55))
	name.add_theme_font_size_override("font_size", 14 if not big else 16)
	var num := Label.new()
	num.text = str(count)
	num.add_theme_color_override("font_color", Color.WHITE)
	num.add_theme_color_override("font_outline_color", col.darkened(0.5))
	num.add_theme_constant_override("outline_size", 4)
	num.add_theme_font_size_override("font_size", 18 if not big else 22)
	row.add_child(name)
	row.add_child(num)
	p.add_child(row)
	return p

static func heading(text: String, size: int = 16, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l
