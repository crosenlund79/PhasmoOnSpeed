extends Screen
## Competitive multiplayer lobby: host or join, names, connected hunters,
## house selection (host), ready status and start.

var message := ""
var status_label: Label
var players_box: VBoxContainer
var connect_box: VBoxContainer
var room_box: VBoxContainer
var name_edit: LineEdit
var addr_edit: LineEdit
var port_edit: LineEdit
var ready_button: Button
var start_button: Button
var house_buttons := {}
var difficulty_buttons := {}
var pause_limit_check: CheckBox
var _ready_state := false

func _ready() -> void:
	add_backdrop("ui/menu_background.png", 0.6)
	var v := centered_column(1100, 30)
	var t := Art.heading("Competitive Hunt", 46, Color(0.93, 0.85, 0.65))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_color_override("font_outline_color", Color.BLACK)
	t.add_theme_constant_override("outline_size", 8)
	v.add_child(t)
	var sub := Art.label("Two to four rival investigators. One entity. The highest score wins — friendships optional.", 18, Color(0.82, 0.78, 0.7), Art.font_italic)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	status_label = Art.label(message if message != "" else Net.status, 17, Color(1.0, 0.86, 0.6), Art.font_heading)
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(status_label)
	connect_box = parchment_box(v, Vector2(1100, 0))
	_build_connect()
	room_box = parchment_box(v, Vector2(1100, 0))
	_build_room()
	var b := HBoxContainer.new()
	b.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(b)
	b.add_child(Art.button("Leave", func():
		Net.leave()
		Game.goto_menu(), 220))
	Net.lobby_changed.connect(_refresh)
	Net.status_changed.connect(func(s): status_label.text = s)
	Net.connection_lost.connect(func(r):
		status_label.text = r
		_refresh())
	_refresh()

func _build_connect() -> void:
	connect_box.add_child(Art.heading("Join or host", 24))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	connect_box.add_child(row)
	row.add_child(Art.label("Name", 18))
	name_edit = LineEdit.new()
	name_edit.text = SaveData.settings().get("player_name", "Investigator")
	name_edit.max_length = 20
	name_edit.custom_minimum_size = Vector2(220, 0)
	row.add_child(name_edit)
	row.add_child(Art.label("Host address", 18))
	addr_edit = LineEdit.new()
	addr_edit.text = str(SaveData.settings().get("last_address", "127.0.0.1"))
	addr_edit.custom_minimum_size = Vector2(220, 0)
	row.add_child(addr_edit)
	row.add_child(Art.label("Port", 18))
	port_edit = LineEdit.new()
	port_edit.text = str(SaveData.settings().get("last_port", Net.DEFAULT_PORT))
	port_edit.custom_minimum_size = Vector2(90, 0)
	row.add_child(port_edit)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	connect_box.add_child(buttons)
	buttons.add_child(Art.button("Host Game", _host, 260))
	buttons.add_child(Art.button("Join Game", _join, 260))
	var help := Art.label("LAN: the host shares their local IP address (e.g. 192.168.x.x). Internet: the host forwards UDP port %d on their router to their PC and shares their public IP." % Net.DEFAULT_PORT, 14, Color(0.35, 0.27, 0.2), Art.font_italic)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(1040, 0)
	connect_box.add_child(help)

func _build_room() -> void:
	room_box.add_child(Art.heading("Hunters", 24))
	players_box = VBoxContainer.new()
	players_box.add_theme_constant_override("separation", 4)
	room_box.add_child(players_box)
	room_box.add_child(Art.heading("House", 22))
	var houses := HBoxContainer.new()
	houses.add_theme_constant_override("separation", 8)
	room_box.add_child(houses)
	for id in Game.house_ids:
		var hid: String = id
		var b := Art.button(Game.house(id)["name"], func(): Net.set_house(hid), 200)
		b.add_theme_font_size_override("font_size", 16)
		b.toggle_mode = true
		houses.add_child(b)
		house_buttons[id] = b
	# Match options — the host decides for everyone.
	var opts := HBoxContainer.new()
	opts.add_theme_constant_override("separation", 8)
	room_box.add_child(opts)
	opts.add_child(Art.heading("Difficulty", 22))
	for d in [["beginner", "Beginner"], ["normal", "Normal"], ["nightmare", "Nightmare"]]:
		var did: String = d[0]
		var b := Art.button(d[1], func(): Net.set_option("difficulty", did), 150)
		b.add_theme_font_size_override("font_size", 16)
		b.toggle_mode = true
		opts.add_child(b)
		difficulty_buttons[did] = b
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(24, 0)
	opts.add_child(gap)
	pause_limit_check = CheckBox.new()
	pause_limit_check.text = "Limit Menu Pause to %d Seconds" % int(Net.PAUSE_LIMIT)
	for c in ["font_color", "font_pressed_color", "font_hover_color", "font_hover_pressed_color", "font_focus_color"]:
		pause_limit_check.add_theme_color_override(c, Color(0.93, 0.85, 0.65))
	pause_limit_check.add_theme_color_override("font_disabled_color", Color(0.7, 0.64, 0.52))
	pause_limit_check.toggled.connect(func(on): Net.set_option("pause_limit", on))
	opts.add_child(pause_limit_check)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	room_box.add_child(actions)
	ready_button = Art.button("Ready", func():
		_ready_state = not _ready_state
		Net.set_ready(_ready_state)
		_refresh(), 260)
	actions.add_child(ready_button)
	start_button = Art.button("Start Match", func(): Net.start_match(), 260)
	actions.add_child(start_button)

func _save_fields() -> void:
	var name := name_edit.text.strip_edges()
	SaveData.set_setting("player_name", name if name != "" else "Investigator")
	SaveData.set_setting("last_address", addr_edit.text.strip_edges())
	SaveData.set_setting("last_port", int(port_edit.text))

func _host() -> void:
	_save_fields()
	_ready_state = false
	Net.host(int(port_edit.text), name_edit.text)
	_refresh()

func _join() -> void:
	_save_fields()
	_ready_state = false
	Net.join(addr_edit.text, int(port_edit.text), name_edit.text)
	_refresh()

func _refresh() -> void:
	var online := Net.is_online()
	connect_box.get_parent().visible = not online
	room_box.get_parent().visible = online
	if not online:
		return
	for c in players_box.get_children():
		c.queue_free()
	var ids := Net.lobby.keys()
	ids.sort()
	for id in ids:
		var p: Dictionary = Net.lobby[id]
		var line := "%s%s   —   %s" % [p["name"], "  (host)" if id == 1 else "", "READY" if p["ready"] else "not ready"]
		players_box.add_child(Art.label(line, 19, Art.INK if p["ready"] else Color(0.4, 0.32, 0.25), Art.font_heading))
	for hid in house_buttons:
		var b: Button = house_buttons[hid]
		b.button_pressed = hid == Net.house
		b.disabled = not Net.is_host()
	for did in difficulty_buttons:
		var db: Button = difficulty_buttons[did]
		db.button_pressed = Net.options.get("difficulty", "normal") == did
		db.disabled = not Net.is_host()
	pause_limit_check.set_pressed_no_signal(Net.options.get("pause_limit", true))
	pause_limit_check.disabled = not Net.is_host()
	ready_button.text = "Not ready" if _ready_state else "Ready"
	start_button.visible = Net.is_host()
	start_button.disabled = not Net.can_start()
	start_button.text = "Start Match" if Net.lobby.size() >= 2 else "Start Match (need a rival)"

func on_escape() -> void:
	Net.leave()
	Game.goto_menu()
