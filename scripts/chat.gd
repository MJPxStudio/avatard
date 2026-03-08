extends CanvasLayer

# ============================================================
# CHAT SYSTEM
# Toggle: Enter opens + focuses input, Escape closes
# Channels: /g  = global, /w <name> = whisper, default = zone
# ============================================================

const MAX_MESSAGES   = 60
const VISIBLE_LINES  = 8
const PANEL_W        = 280.0
const PANEL_H        = 160.0
const INPUT_H        = 22.0
const PAD            = 6.0
const SCREEN_MARGIN  = 8.0

# Channel colours
const COL_ZONE    = Color(0.85, 0.85, 0.85, 1)
const COL_GLOBAL  = Color(0.4,  0.85, 1.0,  1)
const COL_WHISPER = Color(0.9,  0.5,  0.9,  1)
const COL_SYSTEM  = Color(0.9,  0.8,  0.3,  1)
const COL_KILL    = Color(1.0,  0.25, 0.25, 1)
const COL_PARTY   = Color(0.4,  1.0,  0.55, 1)

var _open:        bool    = false
var _fade_timer:  float   = 0.0
const FADE_DELAY: float   = 2.5
var _messages:    Array   = []   # {text, color}

var _root:        Control = null
var _bg:          ColorRect = null
var _scroll:      ScrollContainer = null
var _msg_vbox:    VBoxContainer = null
var _input_field:       LineEdit = null
var _channel_lbl: Label = null

signal chat_submitted(channel: String, target: String, text: String)

func _ready() -> void:
	_build()
	_add_message("Zone", "", "Welcome! /g global | /w <n> whisper | /p <msg> party chat | /invite <n>", COL_SYSTEM)
	_set_open(false)
	_bg.modulate.a = ALPHA_CLOSED

func _process(delta: float) -> void:
	if not _open and _fade_timer > 0:
		_fade_timer -= delta
		if _fade_timer <= 0:
			var tween = get_tree().create_tween()
			tween.tween_property(_bg, "modulate:a", ALPHA_CLOSED, 0.4)

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Background panel — flush bottom right
	_bg          = ColorRect.new()
	_bg.color    = Color(0.04, 0.04, 0.04, 0.78)
	_bg.size     = Vector2(PANEL_W, PANEL_H + INPUT_H + PAD)
	_bg.position = Vector2(0, -(PANEL_H + INPUT_H + PAD))
	_root.add_child(_bg)

	# Scroll area for messages
	_scroll          = ScrollContainer.new()
	_scroll.position = Vector2(PAD, PAD)
	_scroll.size     = Vector2(PANEL_W - PAD * 2, PANEL_H - PAD * 2)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bg.add_child(_scroll)

	_msg_vbox = VBoxContainer.new()
	_msg_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_msg_vbox.add_theme_constant_override("separation", 1)
	_scroll.add_child(_msg_vbox)

	# Channel indicator label
	_channel_lbl          = Label.new()
	_channel_lbl.text     = "[Zone]"
	_channel_lbl.position = Vector2(PAD, PANEL_H - 1)
	_channel_lbl.add_theme_font_size_override("font_size", 8)
	_channel_lbl.add_theme_color_override("font_color", COL_ZONE)
	_bg.add_child(_channel_lbl)

	# Input field
	_input_field         = LineEdit.new()
	_input_field.placeholder_text = "Type a message…"
	_input_field.position      = Vector2(PAD + 36, PANEL_H - 3)
	_input_field.size          = Vector2(PANEL_W - PAD * 2 - 36, INPUT_H)
	_input_field.add_theme_font_size_override("font_size", 9)
	_input_field.add_theme_color_override("font_color", Color(1, 1, 1))
	_input_field.add_theme_color_override("caret_color", Color(1, 1, 1))
	_input_field.add_theme_stylebox_override("normal", _make_input_style())
	_input_field.add_theme_stylebox_override("focus",  _make_input_style())
	_input_field.text_submitted.connect(_on_input_submitted)
	_input_field.text_changed.connect(_on_input_changed)
	_bg.add_child(_input_field)

func _make_input_style() -> StyleBoxFlat:
	var s = StyleBoxFlat.new()
	s.bg_color     = Color(0.1, 0.1, 0.1, 0.9)
	s.border_width_bottom = 1
	s.border_color = Color(0.3, 0.3, 0.3, 1)
	return s

# ── Input handling ──────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER or event.physical_keycode == KEY_ENTER:
			if not _open:
				_set_open(true)
				get_viewport().set_input_as_handled()
			elif _input_field.text.strip_edges() != "":
				# Submit on Enter if text present
				pass  # handled by text_submitted signal
			else:
				_set_open(false)
				get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and _open:
			_set_open(false)
			get_viewport().set_input_as_handled()

func _on_input_changed(text: String) -> void:
	# Update channel label based on prefix
	if text.begins_with("/g ") or text == "/g":
		_channel_lbl.text = "[Global]"
		_channel_lbl.add_theme_color_override("font_color", COL_GLOBAL)
	elif text.begins_with("/w "):
		_channel_lbl.text = "[Whisper]"
		_channel_lbl.add_theme_color_override("font_color", COL_WHISPER)
	else:
		_channel_lbl.text = "[Zone]"
		_channel_lbl.add_theme_color_override("font_color", COL_ZONE)

func _is_spam(text: String) -> bool:
	var run = 1
	for i in range(1, text.length()):
		if text[i] == text[i - 1]:
			run += 1
			if run >= 5: return true
		else:
			run = 1
	if " " not in text and text.length() > 8:
		var has_vowel = false
		for c in text.to_lower():
			if c in "aeiou": has_vowel = true; break
		if not has_vowel: return true
	if " " not in text and text.length() > 6:
		var counts: Dictionary = {}
		for c in text: counts[c] = counts.get(c, 0) + 1
		for c in counts:
			if float(counts[c]) / text.length() > 0.65: return true
	return false

func _on_input_submitted(text: String) -> void:
	text = text.strip_edges()
	if text == "":
		_set_open(false)
		return
	var channel = "zone"
	var target  = ""
	var body    = text
	if text.begins_with("/g "):
		channel = "global"
		body    = text.substr(3)
	elif text == "/g":
		_set_open(false)
		return
	elif text.begins_with("/w "):
		var parts = text.substr(3).split(" ", false, 1)
		if parts.size() < 2:
			add_system_message("Usage: /w <name> <message>")
			_set_open(false)
			return
		channel = "whisper"
		target  = parts[0]
		body    = parts[1]
	elif text.begins_with("/pc ") or text.begins_with("/p "):
		# Party chat
		var offset = 4 if text.begins_with("/pc ") else 3
		var msg = text.substr(offset).strip_edges()
		if msg != "":
			var net = get_tree().root.get_node_or_null("Network")
			if net and net.is_network_connected():
				net.send_chat.rpc_id(1, "party", "", msg)
		_set_open(false)
		return
	elif text == "/invite" or text.begins_with("/invite "):
		var name = text.substr(7).strip_edges()  # strip "/invite"
		if name.is_empty():
			# No argument — use current target if it's a remote player
			var lp = get_tree().root.get_node_or_null("Main/Player")
			if lp and is_instance_valid(lp) and "locked_target" in lp and lp.locked_target != null and is_instance_valid(lp.locked_target):
				if "username" in lp.locked_target and lp.locked_target.username != "":
					name = lp.locked_target.username
		if name.is_empty():
			add_system_message("Usage: /invite <name> — or target a player first")
		else:
			var net = get_tree().root.get_node_or_null("Network")
			if net and net.is_network_connected():
				net.send_party_invite.rpc_id(1, name)
				add_system_message("Sending party invite to %s..." % name)
		_set_open(false)
		return
	elif text.begins_with("/accept "):
		var name = text.substr(8).strip_edges()
		if name != "":
			var net = get_tree().root.get_node_or_null("Network")
			if net and net.is_network_connected():
				net.send_party_response.rpc_id(1, name, true)
		_set_open(false)
		return
	elif text.begins_with("/decline "):
		var name = text.substr(9).strip_edges()
		if name != "":
			var net = get_tree().root.get_node_or_null("Network")
			if net and net.is_network_connected():
				net.send_party_response.rpc_id(1, name, false)
		_set_open(false)
		return
	elif text == "/leave":
		var net = get_tree().root.get_node_or_null("Network")
		if net and net.is_network_connected():
			net.send_party_leave.rpc_id(1)
		_set_open(false)
		return
	if body.strip_edges() == "":
		_set_open(false)
		return
	# Client-side spam filter (server also enforces — this gives instant feedback)
	if channel in ["zone", "global"] and _is_spam(body):
		add_system_message("Message blocked: looks like spam.")
		_set_open(false)
		return
	emit_signal("chat_submitted", channel, target, body)
	_input_field.clear()
	_on_input_changed("")
	# Deselect input but keep box visible, then fade after delay
	_open = false
	_input_field.release_focus()
	_root.get_viewport().gui_release_focus()
	_bg.modulate.a = ALPHA_OPEN  # stay bright while delay runs
	_fade_timer = FADE_DELAY

# ── Message display ─────────────────────────────────────────

func _add_message(channel: String, sender: String, text: String, color: Color) -> void:
	var prefix = ""
	match channel:
		"global":  prefix = "[G] "
		"whisper": prefix = "[W] "
		"party":   prefix = "[P] "
		"system":  prefix = ""
		_:         prefix = ""
	var full = ("%s%s: %s" % [prefix, sender, text]) if sender != "" else text
	var lbl = Label.new()
	lbl.text             = full
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 1)
	lbl.add_theme_constant_override("shadow_offset_y", 1)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.custom_minimum_size = Vector2(PANEL_W - PAD * 4, 0)
	_msg_vbox.add_child(lbl)
	_messages.append({"label": lbl, "text": full})
	# Trim old messages
	if _messages.size() > MAX_MESSAGES:
		var old = _messages.pop_front()
		if old["label"] and is_instance_valid(old["label"]):
			old["label"].queue_free()
	# Scroll to bottom
	await get_tree().process_frame
	_scroll.scroll_vertical = _scroll.get_v_scroll_bar().max_value

func add_zone_message(sender: String, text: String) -> void:
	_add_message("zone", sender, text, COL_ZONE)

func add_global_message(sender: String, text: String) -> void:
	_add_message("global", sender, text, COL_GLOBAL)

func add_whisper_message(sender: String, text: String, outgoing: bool = false) -> void:
	var col = COL_WHISPER
	var pfx = ("To %s" % sender) if outgoing else ("From %s" % sender)
	_add_message("whisper", pfx, text, col)

func add_system_message(text: String) -> void:
	_add_message("system", "", text, COL_SYSTEM)

func add_party_message(sender: String, text: String) -> void:
	_add_message("party", sender, text, COL_PARTY)

func add_kill_message(killer: String, victim: String) -> void:
	_add_message("kill", "", "%s was slain by %s" % [victim, killer], COL_KILL)

# ── Visibility ───────────────────────────────────────────────

const ALPHA_OPEN:  float = 1.0
const ALPHA_CLOSED: float = 0.25  # Semi-transparent resting state

func _set_open(value: bool) -> void:
	_open = value
	_bg.visible = true  # Always visible, just different alpha
	if value:
		_fade_timer = 0.0  # cancel any pending auto-fade
		_bg.modulate.a = ALPHA_OPEN
		_input_field.grab_focus()
	else:
		_input_field.release_focus()
		_input_field.clear()
		_on_input_changed("")
		_root.get_viewport().gui_release_focus()
		var tween = get_tree().create_tween()
		tween.tween_property(_bg, "modulate:a", ALPHA_CLOSED, 0.25)

func is_open() -> bool:
	return _open
