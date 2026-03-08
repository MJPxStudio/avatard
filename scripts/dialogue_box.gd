extends CanvasLayer

# ============================================================
# DIALOGUE BOX — Screen-space dialogue panel.
# Opened by npc.gd via open(npc_name, pages).
# Player movement is blocked while dialogue is open.
# F advances pages, Escape closes early.
# ============================================================

const TYPEWRITER_SPEED: float = 0.03   # seconds per character
const PANEL_H:          float = 110.0
const PANEL_MARGIN:     float = 14.0

var _pages:       Array  = []
var _page_index:  int    = 0
var _full_text:   String = ""
var _shown_chars: int    = 0
var _typewriter:  float  = 0.0
var _revealed:    bool   = false   # true once all chars shown

var _name_label:  Label  = null
var _text_label:  Label  = null
var _hint_label:  Label  = null
var _panel:       ColorRect = null
var _btn_accept:  Button = null
var _btn_decline: Button = null
var _btn_complete: Button = null
var _quest_context: Dictionary = {}
var _kbd_index: int = 0          # currently highlighted button index
var _active_btns: Array = []     # buttons currently shown

func _ready() -> void:
	layer = 90  # above world, below fade overlay
	_build()

func _build() -> void:
	# Dark panel — full width at bottom of screen with small side margins
	_panel                = ColorRect.new()
	_panel.color          = Color(0.06, 0.06, 0.08, 0.92)
	_panel.anchor_left    = 0.0
	_panel.anchor_right   = 1.0
	_panel.anchor_top     = 1.0
	_panel.anchor_bottom  = 1.0
	_panel.offset_left    = PANEL_MARGIN
	_panel.offset_right   = -PANEL_MARGIN
	_panel.offset_top     = -PANEL_H - PANEL_MARGIN
	_panel.offset_bottom  = -PANEL_MARGIN
	add_child(_panel)

	# Border line at top of panel — full width via anchors
	var border          = ColorRect.new()
	border.color        = Color(0.8, 0.7, 0.3, 0.9)
	border.anchor_right = 1.0
	border.offset_bottom = 2
	_panel.add_child(border)

	# Speaker name tag
	_name_label = Label.new()
	_name_label.position = Vector2(PANEL_MARGIN, 8)
	_name_label.add_theme_font_size_override("font_size", 10)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3, 1.0))
	_name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_name_label.add_theme_constant_override("shadow_offset_x", 1)
	_name_label.add_theme_constant_override("shadow_offset_y", 1)
	_panel.add_child(_name_label)

	# Dialogue text
	_text_label = Label.new()
	_text_label.position              = Vector2(PANEL_MARGIN, 26)
	_text_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_text_label.offset_left           = PANEL_MARGIN
	_text_label.offset_right          = -PANEL_MARGIN
	_text_label.offset_top            = 22
	_text_label.offset_bottom         = -28  # leave room for quest buttons
	_text_label.autowrap_mode      = TextServer.AUTOWRAP_WORD_SMART
	_text_label.add_theme_font_size_override("font_size", 10)
	_text_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92, 1.0))
	_text_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_text_label.add_theme_constant_override("shadow_offset_x", 1)
	_text_label.add_theme_constant_override("shadow_offset_y", 1)
	_panel.add_child(_text_label)

	# Continue / close hint — bottom-right by default
	_hint_label = Label.new()
	_hint_label.anchor_left   = 1.0
	_hint_label.anchor_right  = 1.0
	_hint_label.anchor_top    = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_left   = -160
	_hint_label.offset_right  = -PANEL_MARGIN
	_hint_label.offset_top    = -20
	_hint_label.offset_bottom = -6
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 8)
	_hint_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6, 1.0))
	_panel.add_child(_hint_label)
	_build_quest_buttons()

func _build_quest_buttons() -> void:
	# HBoxContainer centered at the bottom of the panel
	var hbox = HBoxContainer.new()
	hbox.anchor_left    = 0.0
	hbox.anchor_right   = 1.0
	hbox.anchor_top     = 1.0
	hbox.anchor_bottom  = 1.0
	hbox.offset_left    = PANEL_MARGIN
	hbox.offset_right   = -PANEL_MARGIN
	hbox.offset_top     = -26
	hbox.offset_bottom  = -4
	hbox.alignment      = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	_panel.add_child(hbox)

	_btn_accept = Button.new()
	_btn_accept.text    = "Accept"
	_btn_accept.visible = false
	_btn_accept.custom_minimum_size = Vector2(72, 0)
	_btn_accept.add_theme_font_size_override("font_size", 9)
	hbox.add_child(_btn_accept)
	_btn_accept.pressed.connect(_on_accept)

	_btn_decline = Button.new()
	_btn_decline.text    = "Decline"
	_btn_decline.visible = false
	_btn_decline.custom_minimum_size = Vector2(72, 0)
	_btn_decline.add_theme_font_size_override("font_size", 9)
	hbox.add_child(_btn_decline)
	_btn_decline.pressed.connect(_on_decline)

	_btn_complete = Button.new()
	_btn_complete.text    = "Complete"
	_btn_complete.visible = false
	_btn_complete.custom_minimum_size = Vector2(80, 0)
	_btn_complete.add_theme_font_size_override("font_size", 9)
	hbox.add_child(_btn_complete)
	_btn_complete.pressed.connect(_on_complete)

func open(speaker: String, pages: Array, quest_context: Dictionary = {}) -> void:
	_pages         = pages
	_page_index    = 0
	_quest_context = quest_context
	_name_label.text = speaker
	_show_page(0)
	# Lock player movement
	var player = get_tree().get_first_node_in_group("local_player")
	if player and player.has_method("set_dialogue_open"):
		player.set_dialogue_open(true)

func _show_page(idx: int) -> void:
	_full_text    = _pages[idx] if idx < _pages.size() else ""
	_shown_chars  = 0
	_typewriter   = 0.0
	_revealed     = false
	_text_label.text = ""
	_update_hint()

func _update_hint() -> void:
	var on_last = (_page_index >= _pages.size() - 1)
	var has_quest = not _quest_context.is_empty()
	# Hide quest buttons by default
	_active_btns = []
	if _btn_accept:   _btn_accept.visible   = false
	if _btn_decline:  _btn_decline.visible  = false
	if _btn_complete: _btn_complete.visible = false
	if not _revealed:
		_hint_label.text = ""
		_hint_label_normal()
	elif not on_last:
		_hint_label.text = "[F] Continue"
		_hint_label_normal()
	elif has_quest and on_last:
		# Show quest buttons and set up keyboard navigation
		_hint_label.text = ""
		_hint_label_quest()
		var action = _quest_context.get("action", "")
		_active_btns = []
		if action == "offer":
			_btn_accept.visible  = true
			_btn_decline.visible = true
			_active_btns = [_btn_accept, _btn_decline]
		elif action == "complete":
			_btn_complete.visible = true
			_active_btns = [_btn_complete]
		_kbd_index = 0
		_update_btn_focus()
	else:
		_hint_label.text = "[F] Close"
		_hint_label_normal()

func _hint_label_normal() -> void:
	_hint_label.anchor_left              = 1.0
	_hint_label.anchor_right             = 1.0
	_hint_label.offset_left              = -160
	_hint_label.offset_right             = -PANEL_MARGIN
	_hint_label.offset_top               = -20
	_hint_label.offset_bottom            = -6
	_hint_label.horizontal_alignment     = HORIZONTAL_ALIGNMENT_RIGHT

func _hint_label_quest() -> void:
	_hint_label.anchor_left              = 0.0
	_hint_label.anchor_right             = 1.0
	_hint_label.offset_left              = PANEL_MARGIN
	_hint_label.offset_right             = -PANEL_MARGIN
	_hint_label.offset_top               = -42
	_hint_label.offset_bottom            = -28
	_hint_label.horizontal_alignment     = HORIZONTAL_ALIGNMENT_CENTER

func _update_btn_focus() -> void:
	if _active_btns.is_empty():
		return
	_kbd_index = clamp(_kbd_index, 0, _active_btns.size() - 1)
	_active_btns[_kbd_index].grab_focus()

func _process(delta: float) -> void:
	if _revealed:
		return
	_typewriter += delta
	while _typewriter >= TYPEWRITER_SPEED and _shown_chars < _full_text.length():
		_typewriter   -= TYPEWRITER_SPEED
		_shown_chars  += 1
		_text_label.text = _full_text.left(_shown_chars)
	if _shown_chars >= _full_text.length():
		_revealed = true
		_update_hint()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Arrow key navigation between quest buttons
		if not _active_btns.is_empty() and _revealed:
			if event.physical_keycode == KEY_LEFT or event.physical_keycode == KEY_RIGHT:
				_kbd_index = (_kbd_index + 1) % _active_btns.size() if event.physical_keycode == KEY_RIGHT 					else (_kbd_index - 1 + _active_btns.size()) % _active_btns.size()
				_update_btn_focus()
				get_viewport().set_input_as_handled()
				return
			if event.physical_keycode == KEY_ENTER:
				_active_btns[_kbd_index].pressed.emit()
				get_viewport().set_input_as_handled()
				return
		if event.physical_keycode == KEY_F:
			if not _revealed:
				# Skip typewriter — show full text immediately
				_shown_chars     = _full_text.length()
				_text_label.text = _full_text
				_revealed        = true
				_update_hint()
			elif _page_index < _pages.size() - 1:
				_page_index += 1
				_show_page(_page_index)
			elif _quest_context.is_empty():
				# No quest — F closes as normal
				_close()
			# else: quest buttons are showing — player must click Accept/Decline/Complete
		elif event.physical_keycode == KEY_ESCAPE:
			_close()

func _on_accept() -> void:
	var qid = _quest_context.get("id", "")
	if qid == "":
		_close()
		return
	var net = get_tree().root.get_node_or_null("Network")
	var player = get_tree().get_first_node_in_group("local_player")
	if net and net.has_method("send_quest_accept"):
		net.send_quest_accept.rpc_id(1, qid)
	if player and player.has_method("accept_quest_locally"):
		player.accept_quest_locally(qid)
	_close()

func _on_decline() -> void:
	_close()

func _on_complete() -> void:
	var qid = _quest_context.get("id", "")
	if qid == "":
		_close()
		return
	var net = get_tree().root.get_node_or_null("Network")
	if net and net.has_method("send_quest_complete"):
		net.send_quest_complete.rpc_id(1, qid)
	_close()

func _close() -> void:
	var player = get_tree().get_first_node_in_group("local_player")
	if player and player.has_method("set_dialogue_open"):
		# Deferred so dialogue_open stays true for the rest of this frame.
		# Without this, closing via Space clears the flag before _physics_process
		# runs its attack check — causing an attack on the same frame as close.
		player.call_deferred("set_dialogue_open", false)
	queue_free()
