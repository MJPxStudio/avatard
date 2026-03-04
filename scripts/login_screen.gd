extends CanvasLayer

var username_field: LineEdit
var connect_btn: Button
var status_label: Label

func _ready() -> void:
	_build_ui()
	Network.connection_succeeded.connect(_on_connected)
	Network.connection_failed.connect(_on_connection_failed)
	Network.login_accepted_client.connect(_on_login_accepted)
	Network.login_denied_client.connect(_on_login_denied)
	Network.launch_as_client()

func _build_ui() -> void:
	var panel = PanelContainer.new()
	panel.size = Vector2(240, 130)
	panel.position = Vector2(360, 205)
	add_child(panel)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)
	var title = Label.new()
	title.text = "AVATARD"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color("ffd700"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	username_field = LineEdit.new()
	username_field.placeholder_text = "Enter username..."
	username_field.max_length = 24
	username_field.text_submitted.connect(_on_submit)
	vbox.add_child(username_field)
	connect_btn = Button.new()
	connect_btn.text = "PLAY"
	connect_btn.pressed.connect(_on_play_pressed)
	connect_btn.disabled = true
	vbox.add_child(connect_btn)
	status_label = Label.new()
	status_label.text = "Connecting..."
	status_label.add_theme_font_size_override("font_size", 9)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(status_label)

func _on_connected() -> void:
	status_label.text = "Connected. Enter username."
	connect_btn.disabled = false
	username_field.grab_focus()

func _on_connection_failed() -> void:
	status_label.text = "Could not connect to server."

func _on_play_pressed() -> void:
	_on_submit(username_field.text)

func _on_submit(username: String) -> void:
	username = username.strip_edges()
	if username.is_empty():
		status_label.text = "Please enter a username."
		return
	connect_btn.disabled = true
	status_label.text = "Logging in..."
	Network.request_login.rpc_id(1, username)

func _on_login_accepted(player_data: Dictionary) -> void:
	visible = false
	get_tree().current_scene.on_player_logged_in(player_data)

func _on_login_denied(reason: String) -> void:
	status_label.text = reason
	connect_btn.disabled = false
