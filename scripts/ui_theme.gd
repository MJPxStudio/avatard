extends Node

# ============================================================
# UI THEME — Village-based UI theming system
# Add this as an Autoload named "UITheme"
# ============================================================

var current_village: String = "leaf"

const THEMES = {
	"leaf": {
		# Core palette
		"panel_bg":        Color("1C0F08"),     # deep dark bark
		"panel_border":    Color("5C3317"),     # aged wood brown
		"panel_accent":    Color("8B6914"),     # worn gold
		"panel_highlight": Color("A0892E"),     # warm gold-green highlight
		"text_primary":    Color("F0E6C8"),     # warm cream
		"text_secondary":  Color("B8A882"),     # muted parchment
		"text_shadow":     Color("000000"),

		# Bars
		"bar_bg":          Color("120800"),     # dark earth
		"hp_fill":         Color("CC3311"),     # warm red
		"chakra_fill":     Color("2E8B7A"),     # teal-green
		"exp_fill":        Color("D4A017"),     # warm gold
		"dash_fill":       Color("4A8B3A"),     # forest green
		"dash_fill_dim":   Color("2A4A1A"),     # dim green reloading

		# Interactive
		"hover_bg":        Color(0.3, 0.5, 0.15, 0.25),
		"selected_bg":     Color(0.35, 0.55, 0.1, 0.4),
		"selected_border": Color("7AB832"),

		# Cooldown overlay
		"cooldown_overlay": Color(0, 0, 0, 0.65),

		# Chat
		"chat_bg":         Color(0.07, 0.04, 0.02, 0.82),
		"chat_border":     Color("3D2010"),
		"chat_input_bg":   Color(0.10, 0.06, 0.03, 0.92),

		# Tooltip
		"tooltip_bg":      Color("1C0F08"),
		"tooltip_border":  Color("5C3317"),

		# Rank colors — same across villages
		"rank_d":  Color("aaaaaa"),
		"rank_c":  Color("55dd55"),
		"rank_b":  Color("5599ff"),
		"rank_a":  Color("dd44dd"),
		"rank_s":  Color("ffaa00"),

		# Level/gold label colors
		"level_color": Color("D4A017"),
		"gold_color":  Color("FFD700"),
		"run_color":   Color("7AB832"),
	}
}

func color(key: String) -> Color:
	var theme = THEMES.get(current_village, THEMES["leaf"])
	return theme.get(key, Color.WHITE)

func set_village(village: String) -> void:
	if THEMES.has(village):
		current_village = village
