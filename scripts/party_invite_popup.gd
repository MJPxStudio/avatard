extends CanvasLayer

# ============================================================
# PARTY INVITE POPUP
# Small toast-style popup, slides in from bottom-right.
# Auto-dismisses after 15s.
# ============================================================

const TIMEOUT    := 15.0
const PANEL_W    := 200.0
const PANEL_H    := 80.0
const MARGIN     := 16.0  # distance from screen edge at rest

signal responded(inviter_name: String, accepted: bool)

var _inviter_name:   String = ""
var _timer:          float  = 0.0
var _countdown_lbl:  Label  = null
var _msg_lbl:        Label  = null
var _panel_ctrl:     Control = null

func _ready() -> void:
	layer = 100
	_build()

func _build() -> void:
	visible = false

	# Root control — anchored bottom-right
	_panel_ctrl = Control.new()
	_panel_ctrl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel_ctrl.anchor_left   = 1.0
	_panel_ctrl.anchor_top    = 1.0
	_panel_ctrl.anchor_right  = 1.0
	_panel_ctrl.anchor_bottom = 1.0
	_panel_ctrl.offset_left   = -(PANEL_W + MARGIN)
	_panel_ctrl.offset_top    = -(PANEL_H + MARGIN)
	_panel_ctrl.offset_right  = -MARGIN
	_panel_ctrl.offset_bottom = -MARGIN
	_panel_ctrl.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	add_child(_panel_ctrl)

	# Background panel with rounded corners
	var bg         = Panel.new()
	bg.size        = Vector2(PANEL_W, PANEL_H)
	bg.position    = Vector2.ZERO
	var bg_style   = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.06, 0.06, 0.1, 0.95)
	bg_style.set_corner_radius_all(6)
	bg_style.set_content_margin_all(0)
	bg.add_theme_stylebox_override("panel", bg_style)
	_panel_ctrl.add_child(bg)

	# Accent bar — rounded left corners only
	var accent       = Panel.new()
	accent.size      = Vector2(3, PANEL_H)
	accent.position  = Vector2.ZERO
	var acc_style    = StyleBoxFlat.new()
	acc_style.bg_color = Color(0.4, 0.8, 0.45, 1.0)
	acc_style.corner_radius_top_left    = 6
	acc_style.corner_radius_bottom_left = 6
	acc_style.corner_radius_top_right    = 0
	acc_style.corner_radius_bottom_right = 0
	acc_style.set_content_margin_all(0)
	accent.add_theme_stylebox_override("panel", acc_style)
	_panel_ctrl.add_child(accent)

	# Title
	var title    = Label.new()
	title.text   = "Party Invite"
	title.position = Vector2(10, 6)
	title.add_theme_font_size_override("font_size", 9)
	title.add_theme_color_override("font_color", Color(0.5, 0.95, 0.6, 1.0))
	_panel_ctrl.add_child(title)

	# Inviter message
	_msg_lbl     = Label.new()
	_msg_lbl.text = "..."
	_msg_lbl.position = Vector2(10, 22)
	_msg_lbl.size     = Vector2(PANEL_W - 14, 18)
	_msg_lbl.add_theme_font_size_override("font_size", 8)
	_msg_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9, 1.0))
	_panel_ctrl.add_child(_msg_lbl)

	# Countdown
	_countdown_lbl     = Label.new()
	_countdown_lbl.text = "15s"
	_countdown_lbl.position = Vector2(PANEL_W - 28, 6)
	_countdown_lbl.add_theme_font_size_override("font_size", 7)
	_countdown_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
	_panel_ctrl.add_child(_countdown_lbl)

	# Buttons row
	var accept_btn  = _make_btn("Accept",  Color(0.12, 0.48, 0.18), func(): _on_accept())
	accept_btn.position = Vector2(10, 50)
	accept_btn.custom_minimum_size = Vector2(84, 20)
	_panel_ctrl.add_child(accept_btn)

	var decline_btn = _make_btn("Decline", Color(0.42, 0.1, 0.1),  func(): _on_decline())
	decline_btn.position = Vector2(102, 50)
	decline_btn.custom_minimum_size = Vector2(84, 20)
	_panel_ctrl.add_child(decline_btn)

func show_invite(inviter_name: String) -> void:
	_inviter_name = inviter_name
	_timer        = TIMEOUT
	if _msg_lbl:
		_msg_lbl.text = "%s wants to party up" % inviter_name
	if _countdown_lbl:
		_countdown_lbl.text = "%ds" % int(ceil(_timer))

	visible = true
	_slide_in()

func _slide_in() -> void:
	# Start offscreen to the right, tween into resting position
	_panel_ctrl.offset_left   = PANEL_W + MARGIN        # start offscreen right
	_panel_ctrl.offset_right  = PANEL_W + MARGIN * 2

	var tween = create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_BACK)
	tween.tween_property(_panel_ctrl, "offset_left",  -(PANEL_W + MARGIN), 0.45)
	tween.parallel().tween_property(_panel_ctrl, "offset_right", -MARGIN, 0.45)

func _slide_out(callback: Callable = Callable()) -> void:
	var tween = create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_property(_panel_ctrl, "offset_left",  PANEL_W + MARGIN, 0.25)
	tween.parallel().tween_property(_panel_ctrl, "offset_right", PANEL_W + MARGIN * 2, 0.25)
	tween.tween_callback(func():
		visible = false
		if callback.is_valid():
			callback.call()
	)

func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _countdown_lbl:
		_countdown_lbl.text = "%ds" % max(int(ceil(_timer)), 0)
	if _timer <= 0.0:
		_dismiss()

func _make_btn(label: String, bg: Color, callback: Callable) -> Button:
	var btn = Button.new()
	btn.text       = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 8)
	btn.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	var s      = StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(2)
	s.set_content_margin_all(3)
	btn.add_theme_stylebox_override("normal", s)
	var sh     = StyleBoxFlat.new()
	sh.bg_color = bg.lightened(0.2)
	sh.set_corner_radius_all(2)
	sh.set_content_margin_all(3)
	btn.add_theme_stylebox_override("hover", sh)
	btn.pressed.connect(callback)
	return btn

func _on_accept() -> void:
	var name = _inviter_name
	_slide_out(func(): responded.emit(name, true))

func _on_decline() -> void:
	var name = _inviter_name
	_slide_out(func(): responded.emit(name, false))

func _dismiss() -> void:
	_slide_out()
