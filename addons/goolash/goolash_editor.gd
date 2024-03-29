@tool
class_name GoolashEditor extends EditorPlugin

signal editing_layer_changed
signal selected_keyframe_changed
signal selected_brush_changed
signal brush_edited

enum {TOOL_SELECT, TOOL_PAINT, TOOL_FILL, TOOL_EYEDROPPER, TOOL_OVAL, TOOL_RECT, TOOL_SHAPE, TOOL_SMOOTH}
enum {ACTION_NONE, ACTION_WARP, ACTION_PAINT, ACTION_OVAL, ACTION_RECT, ACTION_SHAPE, ACTION_MOVE, ACTION_SELECT_RECT, ACTION_SMOOTH}
enum {PAINT_MODE_FRONT, PAINT_MODE_BEHIND, PAINT_MODE_INSIDE}
enum {WARP_EASE_SMOOTH, WARP_EASE_SHARP, WARP_EASE_LINEAR, WARP_EASE_RANDOM}

enum {MAIN_SCREEN_2D, MAIN_SCREEN_3D, MAIN_SCREEN_SCRIPT}

static var editor: GoolashEditor

static var godot_accent_color: Color
static var godot_selection_color: Color

const TextureEyedropper = preload("res://addons/goolash/icons/ColorPick.svg")
const TextureFill = preload("res://addons/goolash/icons/CursorBucket.svg")
const StrokeEraseMaterial = preload("res://addons/goolash/shading/brush_erase_material.tres")
const StrokeRegularMaterial = null

static var KEYFRAME_SCRIPT
static var KEYFRAME_SCRIPT_CUSTOM

var key_add_frame := KEY_5
var key_add_keyframe := KEY_6
var key_add_keyframe_blank := KEY_7
var key_add_script := KEY_9
var key_tool_select_paint_brush := KEY_B
var key_tool_select_oval_brush := KEY_O
var key_tool_select_rectangle_brush := KEY_M
var key_tool_select_shape_brush := KEY_Y
var key_tool_select_fill := KEY_G
var key_play := KEY_S
var key_frame_next := KEY_D
var key_frame_previous := KEY_A
var key_tool_size_decrease := KEY_BRACKETLEFT
var key_tool_size_increase := KEY_BRACKETRIGHT
var key_erase_mode := KEY_X

static var hud
static var timeline

var _current_action: int
var _action_position_previous: Vector2
var _action_rmb := false
var _action_stroke: BrushStroke
var _action_brush_inside: BrushStroke

var default_swatches := PackedColorArray([
		Color("fc9735"), Color("ff192b"), Color("780d2a"),
		Color("ffd900"), Color("ff5f00"), Color("3f2617"),
		Color("3f2617"), Color("73a110"), Color("393a28"),
		Color("a8e6cf"), Color("299176"), Color("296458"),
		Color("6ec6ff"), Color("387cd5"), Color("2e397e"),
		Color("fc7a93"), Color("e21077"), Color("ffffff"),
		Color("000000"), Color("181923"), Color("37353c"),
		Color("696764"), Color("c1b3ac"), Color("ffffff"),
	])
var current_tool: int = TOOL_PAINT
var current_tool_override: int = -1
var current_color: Color = Color.WHITE

var current_paint_mode := PAINT_MODE_FRONT
var current_warp_ease := WARP_EASE_SMOOTH

var _action_paint_size: float = 16.0
var _action_paint_erase_size: float = 32.0

var _action_warp_size: float = 60.0
var _action_warp_cut_angle: float = deg_to_rad(30.0)
var _action_warp_size_preview_t: float = 0.0

var _pen_pressure: float = 0.0

static var onion_skin_enabled := true
static var onion_skin_frames: int = 1
static var erase_mode := false

var editing_node
var _editing_brush: Brush2D
static var selected_keyframe: BrushKeyframe2D:
	set(value):
		selected_keyframe = value
		editor.selected_keyframe_changed.emit()
var is_editing := false
var _selected_highlight: float = 0.0

var canvas_transform_previous

static var allow_custom_cursor := true
var allow_hide_cursor := false

var button_select_mode: Button

var _strokes_before := []

var shader_anti_alias := false
var shader_boil := false


func _enter_tree():
	editor = self
	set_process(false)
	
	godot_accent_color = EditorInterface.get_editor_settings().get_setting("interface/theme/accent_color")
	godot_selection_color = Color("ff8000")
	
	
	_init_project_settings()
	_load_project_settings(true)
	
	add_custom_type("BrushAnimation2D", "Node2D", load("res://addons/goolash/brush_animation2d.gd"), null)
	
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	
	
	hud = load("res://addons/goolash/ui/hud.tscn").instantiate()
	hud.visible = false
	hud.theme = EditorInterface.get_editor_theme()
	EditorInterface.get_editor_viewport_2d().get_parent().get_parent().add_child(hud)
	
	timeline = load("res://addons/goolash/ui/timeline.tscn").instantiate()
	add_control_to_bottom_panel(timeline, "Timeline")
	
	ProjectSettings.settings_changed.connect(_on_settings_changed)
	
	add_autoload_singleton("Goolash", "res://addons/goolash/goolash.gd")
	
	var toolbar = get_editor_interface().get_editor_main_screen().get_child(0).get_child(0).get_child(0).get_child(0)
	button_select_mode = toolbar.get_child(0)
	var button_move_mode: Button = toolbar.get_child(2)
	var button_rotate_mode: Button = toolbar.get_child(4)
	var button_scale_mode: Button = toolbar.get_child(6)
	
	button_select_mode.pressed.connect(_on_mode_changed)
	button_move_mode.pressed.connect(_on_mode_changed)
	button_rotate_mode.pressed.connect(_on_mode_changed)
	button_scale_mode.pressed.connect(_on_mode_changed)
	
	KEYFRAME_SCRIPT = preload("res://addons/goolash/brush_keyframe2d.gd")
	KEYFRAME_SCRIPT_CUSTOM = preload("res://addons/goolash/frame_script.gd")


func _on_mode_changed():
	is_editing = is_instance_valid(editing_node) and button_select_mode.button_pressed
	
	EditorInterface.inspect_object(editing_node)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _init_project_settings():
	## Animation
	_add_project_setting("animation", "default_fps", 12)
	_add_project_setting("animation", "onion_skin_enabled", true)
	_add_project_setting("animation", "onion_skin_frames", 2)
	
	## Painting
	var default_swatches := PackedColorArray([
		Color("fc9735"), Color("ff192b"), Color("780d2a"),
		Color("ffd900"), Color("ff5f00"), Color("3f2617"),
		Color("3f2617"), Color("73a110"), Color("393a28"),
		Color("a8e6cf"), Color("299176"), Color("296458"),
		Color("6ec6ff"), Color("387cd5"), Color("2e397e"),
		Color("fc7a93"), Color("e21077"), Color("ffffff"),
		Color("000000"), Color("181923"), Color("37353c"),
		Color("696764"), Color("c1b3ac"), Color("ffffff"),
	])
	_add_project_setting("painting", "default_swatches", default_swatches)
	_add_project_setting("painting", "default_paint_size", 8.0)
	
	## Rendering
	_add_project_setting("rendering", "anti-alias", true)
	_add_project_setting("rendering", "boiling", true)
	
	
	_add_keybind("tools", "paint_brush_tool", "key_tool_select_paint_brush", KEY_B)
	_add_keybind("tools", "oval_brush_tool", "key_tool_select_oval_brush", KEY_O)
	_add_keybind("tools", "rectangle_brush_tool", "key_tool_select_rectangle_brush", KEY_M)
	_add_keybind("tools", "shape_brush_tool", "key_tool_select_shape_brush", KEY_Y)
	_add_keybind("tools", "fill_tool", "key_tool_select_fill", KEY_G)
	_add_keybind("tools", "incease_tool_size", "key_tool_size_decrease", KEY_BRACKETLEFT)
	_add_keybind("tools", "decrease_tool_size", "key_tool_size_increase", KEY_BRACKETRIGHT)
	_add_keybind("timeline", "play_pause", "key_play", KEY_S)
	_add_keybind("timeline", "next_frame", "key_frame_next", KEY_D)
	_add_keybind("timeline", "previous_frame", "key_frame_previous", KEY_A)
	_add_keybind("timeline", "insert_frame", "key_add_frame", KEY_5)
	_add_keybind("timeline", "add_keyframe", "key_add_keyframe", KEY_6)
	_add_keybind("timeline", "add_blank_keyframe", "key_add_keyframe_blank", KEY_7)
	_add_keybind("timeline", "add_script_to_keyframe", "key_add_script", KEY_9)


var keybind_settings: Dictionary

func _add_keybind(section: String, alias: String, variable: String, default_key: int):
	section = "shortcuts/%s" % section
	var character = char(default_key)
	
	
	_add_project_setting(section, alias, character)
	keybind_settings[variable] = "goolash/%s/%s" % [section, alias]


func _add_project_setting(category, name: String, default_value) -> void:
	var path = "goolash/%s/%s" % [category, name]
	
	if ProjectSettings.has_setting(path):
		return
	ProjectSettings.set_setting(path, default_value)
	ProjectSettings.set_initial_value(path, default_value)


func _load_project_settings(init := false):
	Goolash.default_fps = ProjectSettings.get_setting_with_override("goolash/animation/default_fps")
	onion_skin_enabled = ProjectSettings.get_setting_with_override("goolash/animation/onion_skin_enabled")
	onion_skin_frames = ProjectSettings.get_setting_with_override("goolash/animation/onion_skin_frames")
	
	var project_default_swatches = ProjectSettings.get_setting_with_override("goolash/painting/default_swatches")
	if default_swatches != project_default_swatches:
		default_swatches = project_default_swatches
	current_color = default_swatches[0]
	
	var shader_anti_alias_setting = ProjectSettings.get_setting_with_override("goolash/rendering/anti-alias")
	var shader_boil_setting = ProjectSettings.get_setting_with_override("goolash/rendering/boiling")
	if shader_anti_alias != shader_anti_alias_setting or shader_boil != shader_boil_setting:
		shader_anti_alias = shader_anti_alias_setting
		shader_boil = shader_boil_setting
		if not init:
			write_shader(shader_anti_alias, shader_boil)
	
	for variable in keybind_settings.keys():
		var path = keybind_settings[variable]
		var value: String = ProjectSettings.get_setting_with_override(path)
		
		var value_changed := false
		if value != value.to_upper():
			value = value.to_upper()
			value_changed = true
		if value.length() > 1:
			value_changed = true
			value = value[value.length()-1]
		if value_changed:
			ProjectSettings.set_setting(path, value)
		var keycode = value.unicode_at(0)
		self[variable] = keycode


func _on_settings_changed():
	_load_project_settings()


func _exit_tree() -> void:
	remove_custom_type("BrushAnimation2D")
	
	remove_control_from_bottom_panel(timeline)
	if is_instance_valid(timeline):
		timeline.queue_free()
	
	if is_instance_valid(hud):
		hud.queue_free()
	
	
	var toolbar = get_editor_interface().get_editor_main_screen().get_child(0).get_child(0).get_child(0).get_child(0)
	var button_move_mode: Button = toolbar.get_child(2)
	var button_rotate_mode: Button = toolbar.get_child(4)
	var button_scale_mode: Button = toolbar.get_child(6)
	
	button_select_mode.pressed.disconnect(_on_mode_changed)
	button_move_mode.pressed.disconnect(_on_mode_changed)
	button_rotate_mode.pressed.disconnect(_on_mode_changed)
	button_scale_mode.pressed.disconnect(_on_mode_changed)


func _handles(object) -> bool:
	#if not button_select_mode.button_pressed:
		#return false
	if object is BrushAnimation2D or object is BrushKeyframe2D or object is Brush2D or object is Brush3D or object is BrushClip3D:
		return true
	return false

#region Node Selection

func _on_selection_changed():
	var selection := get_editor_interface().get_selection()
	var selected_nodes = selection.get_selected_nodes()
	selected_keyframe = null
	
	if selected_nodes.size() == 1:
		if select_node(selected_nodes[0]):
			return
	
	if editing_node:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		timeline.load_brush_animation(null)
		_edit_node_brush_complete()


func select_node(selected_node):
	if selected_node is BrushAnimation2D:
		_select_node_brush_animation(selected_node)
		return true
	elif selected_node is BrushKeyframe2D:
		var keyframe: BrushKeyframe2D = selected_node
		_select_node_brush_animation(keyframe.get_clip())
		keyframe.get_clip().goto(keyframe.frame_num)
		selected_keyframe = keyframe
		
		for timeline_keyframe in get_tree().get_nodes_in_group("timeline_keyframes"):
			if timeline_keyframe.keyframe == keyframe:
				timeline_keyframe.grab_focus()
		
		set_editing_layer_num(keyframe.get_layer().layer_num)
		return true
	elif selected_node is Brush2D:
		_select_node_brush(selected_node)
		return true
	elif selected_node is BrushLayer2D:
		var layer: BrushLayer2D = selected_node
		_select_node_brush_animation(layer.get_clip())
		set_editing_layer_num(layer.layer_num)
		return true
	elif selected_node is Brush3D:
		_select_node_brush(selected_node.brush2d)
		editing_node = selected_node
		return true
	elif selected_node is BrushClip3D:
		_select_node_brush_animation(selected_node.brush_animation2d)
		editing_node = selected_node
		return true
	return false


func _select_node_brush(brush):
	_edit_node_start(brush)
	is_editing = button_select_mode.button_pressed


func _select_node_brush_animation(clip):
	_edit_node_start(clip)
	timeline.load_brush_animation(clip)
	make_bottom_panel_item_visible(timeline)
	clip.draw()
	clip.init()
	is_editing = button_select_mode.button_pressed
	return


func _edit_node_start(node):
	editing_node = node
	_get_editing_brush()
	_selected_highlight = 1.0
	
	hud.visible = true
	hud._update_used_colors()
	selected_brush_changed.emit()
	set_process(is_editable(editing_node))


func _edit_node_brush_complete():
	var i := 0
	while i < _editing_brush.strokes.size():
		var stroke_data: BrushStroke = _editing_brush.strokes[i]
		if not stroke_data.is_valid():
			_editing_brush.remove_stroke(stroke_data)
		else:
			i += 1
	
	var previous_editing = editing_node
	_queue_redraw()
	editing_node = null
	hud.visible = false
	set_process(false)

#endregion

#region Input

func _input(event):
	if Input.is_key_pressed(KEY_CTRL):
		return
	if not (_is_main_screen_visible(MAIN_SCREEN_2D) or _is_main_screen_visible(MAIN_SCREEN_3D)):
		return
	if editing_node:
		if event is InputEventKey and event.is_pressed():
			_navigation_input(event)
	#else:
		#TODO: this needs much more work before its usable and not annoying
		#if event is InputEventMouseButton:
			#if event.button_index == MOUSE_BUTTON_LEFT:
				#if event.pressed:
					#try_select_children(get_tree().root)

func try_select_children(parent):
	var children: Array = parent.get_children()
	children.reverse()
	for child in children:
		if child is Brush2D:
			for stroke in child.strokes:
				if Geometry2D.is_point_in_polygon(child.get_local_mouse_position(), stroke.polygon):
					select(child)
					return true
		if try_select_children(child):
			return true
	return false

func select(child):
	await get_tree().process_frame
	EditorInterface.inspect_object(child)
	EditorInterface.get_selection().add_node(child)
	_on_selection_changed()


func _navigation_input(event):
	match event.keycode:
		key_play:
			if editing_node is BrushAnimation2D or editing_node is BrushClip3D:
				if editing_node.is_playing:
					editing_node.stop()
				else:
					editing_node.play()
				return true
		key_frame_previous:
			if editing_node is BrushAnimation2D or editing_node is BrushClip3D:
				editing_node.stop()
				selected_keyframe = null
				if editing_node.previous_frame():
					return true
		key_frame_next:
			if editing_node is BrushAnimation2D or editing_node is BrushClip3D:
				editing_node.stop()
				selected_keyframe = null
				if editing_node.next_frame():
					return true
		key_add_frame:
			if Input.is_key_pressed(KEY_SHIFT):
				_remove_frame()
			else:
				_insert_frame()
			return true
		key_add_keyframe:
			if Input.is_key_pressed(KEY_SHIFT):
				_remove_keyframe()
			else:
				_convert_keyframe()
			return true
		key_add_keyframe_blank:
			if Input.is_key_pressed(KEY_SHIFT):
				_remove_keyframe()
			else:
				_convert_keyframe_blank()
			return true


func _forward_3d_gui_input(viewport_camera, event):
	if not editing_node:
		return false
	if event is InputEventKey:
		_forward_canvas_gui_input(event)
	if editing_node is Brush3D or editing_node is BrushClip3D:
		if event is InputEventMouse:
			var mouse_position = get_mouse_position_on_plane(viewport_camera, event.position, editing_node)
			if event is InputEventMouseButton:
				event.position = mouse_position
				_forward_canvas_gui_input(event)
				return true
			if event is InputEventMouseMotion:
				var event2d = InputEventMouseMotion.new()
				event2d.position = mouse_position
				_forward_canvas_gui_input(event2d)
				if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
					return true
	return false


func get_mouse_position_on_plane(camera: Camera3D, mouse_pos: Vector2, node: Node3D) -> Vector2:
	var camera_transform = camera.global_transform
	
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	
	var local_origin := node.to_local(ray_origin)
	var local_normal = node.to_local(ray_origin + ray_normal) - local_origin
	
	var t = -local_origin.z / local_normal.z
	var intersection = local_origin + local_normal * t
	
	return Vector2(intersection.x, -intersection.y) * 100.0


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not editing_node:
		return false
	
	if event is InputEventMouse:
		return _input_mouse(event)
	elif event is InputEventKey:
		if event.is_pressed():
			return _on_key_pressed(event)
		else:
			return _on_key_released(event)
	return false


func _on_key_pressed(event: InputEventKey) -> bool:
	if Input.is_key_pressed(KEY_CTRL):
		if event.keycode == KEY_CTRL:
			_on_input_key_ctrl_pressed()
		return false
	
	#if not button_select_mode.button_pressed:
		#return false
	
	match event.keycode:
		key_play, key_frame_next, key_frame_previous:
			return true
		KEY_ALT:
			_on_input_key_alt_pressed()
		KEY_Q:
			set_tool(TOOL_SELECT)
			return true
		key_tool_select_paint_brush:
			set_tool(TOOL_PAINT)
			return true
		key_tool_select_rectangle_brush:
			set_tool(TOOL_RECT)
			return true
		key_tool_select_fill:
			set_tool(TOOL_FILL)
			return true
		key_tool_select_oval_brush:
			set_tool(TOOL_OVAL)
			return true
		key_tool_select_shape_brush:
			set_tool(TOOL_SHAPE)
			return true
		key_tool_size_decrease:
			if current_tool == TOOL_PAINT:
				_action_paint_erase_size *= 1 / (2.0 ** (1.0 / 6.0))
				_action_paint_size *= 1 / (2.0 ** (1.0 / 6.0))
				return true
			elif current_tool == TOOL_SELECT:
				_action_warp_size *= 1 / (2.0 ** (1.0 / 6.0))
				_action_warp_size_preview_t = 1.0
				_get_edge_selections(_editing_brush.get_local_mouse_position(), _action_warp_size, current_warp_ease)
				return true
		key_tool_size_increase:
			if current_tool == TOOL_PAINT:
				_action_paint_erase_size *= 2.0 ** (1.0 / 6.0)
				_action_paint_size *= 2.0 ** (1.0 / 6.0)
				return true
			elif current_tool == TOOL_SELECT:
				_action_warp_size *= 2.0 ** (1.0 / 6.0)
				_action_warp_size_preview_t = 1.0
				_get_edge_selections(_editing_brush.get_local_mouse_position(), _action_warp_size, current_warp_ease)
				return true
		key_erase_mode:
			set_erase_mode(true)
			return true
		key_add_script:
			if selected_keyframe:
				add_custom_script_to_keyframe(selected_keyframe)
			return true
	return false


func _on_key_released(event: InputEventKey) -> bool:
	match event.keycode:
		key_erase_mode:
			set_erase_mode(false)
	return false


func _on_input_key_alt_pressed() -> bool:
	#if [TOOL_PAINT, TOOL_OVAL, TOOL_RECT, TOOL_SHAPE, TOOL_FILL].has(current_tool):
	current_tool_override = TOOL_EYEDROPPER
	_queue_redraw()
	return false


func _on_input_key_ctrl_pressed() -> bool:
	#if [TOOL_PAINT, TOOL_OVAL, TOOL_RECT, TOOL_SHAPE].has(current_tool):
	current_tool_override = TOOL_FILL
	_queue_redraw()
	if _editing_brush:
		_editing_brush._request_forward_draw()
	return false


func _input_mouse(event: InputEventMouse) -> bool:
	if not button_select_mode.button_pressed:
		return false
	
	var mouse_position: Vector2
	if editing_node is Brush3D or editing_node is BrushClip3D:
		mouse_position = event.position + Vector2.ONE * 250.0
	else:
		if not _editing_brush:
			return true
		mouse_position = _editing_brush.get_viewport_transform().affine_inverse() * event.position
		mouse_position = _editing_brush.to_local(mouse_position)
	
	if event is InputEventMouseButton:
		var event_mouse_button: InputEventMouseButton = event
		if event_mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if event_mouse_button.pressed:
				return _on_mouse_button_pressed(mouse_position)
			else:
				_on_mouse_button_released(mouse_position)
		elif event_mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			if event_mouse_button.pressed:
				_on_mouse_button_pressed(mouse_position, true)
			else:
				_on_mouse_button_released(mouse_position)
	elif event is InputEventMouseMotion:
		_on_mouse_motion(mouse_position)
	return true


func _on_mouse_motion(mouse_position):
	_queue_redraw()
	match _current_action:
		ACTION_WARP:
			action_warp_process(mouse_position)
		ACTION_SHAPE:
			if not Input.is_key_pressed(KEY_SHIFT):
				action_shape_process(mouse_position)
		ACTION_PAINT:
			action_paint_process(mouse_position)
		ACTION_MOVE:
			action_move_process(mouse_position)
	
	match _get_current_tool():
		TOOL_SELECT:
			if _current_action == ACTION_NONE:
				_get_edge_selections(mouse_position, _action_warp_size, current_warp_ease)
		TOOL_SMOOTH:
			action_smooth_mouse_motion(mouse_position)

func _on_mouse_button_pressed(mouse_position: Vector2, right_mouse_button := false) -> bool:
	if not button_select_mode.button_pressed:
		return false
	if _current_action != ACTION_NONE:
		return true
	_action_rmb = right_mouse_button != erase_mode
	return _action_start(mouse_position)


func _on_mouse_button_released(mouse_position):
	if Input.is_key_pressed(KEY_SHIFT):
		match _current_action:
			ACTION_SHAPE:
				action_shape_process(mouse_position)
				return
	_current_action_complete(mouse_position)

#endregion

func _process(delta):
	if not is_instance_valid(editing_node):
		set_process(false)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if not is_editing:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if get_viewport().canvas_transform != canvas_transform_previous:
		canvas_transform_previous = editing_node.get_viewport().get_screen_transform()
		_queue_redraw()
	
	match _current_action:
		ACTION_SMOOTH:
			_action_smooth_process(delta)
	
	allow_hide_cursor = (
			EditorInterface.get_editor_main_screen().get_child(0).visible and
			hud.get_rect().has_point(hud.get_local_mouse_position()) and
			allow_custom_cursor and 
			DisplayServer.window_is_focused() and
			not Input.is_key_pressed(KEY_SPACE) and
			not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	)
	if (current_tool == TOOL_PAINT or current_tool == TOOL_FILL) and allow_hide_cursor:
		##todo: this needs more checks
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	if current_tool_override == TOOL_EYEDROPPER and not Input.is_key_pressed(KEY_ALT):
		current_tool_override = -1
		_queue_redraw()
	
	if current_tool_override == TOOL_FILL and not Input.is_key_pressed(KEY_CTRL):
		current_tool_override = -1
		_queue_redraw()
	
	if _action_warp_size_preview_t > 0.0:
		_action_warp_size_preview_t -= delta / 0.45
	
	_selected_highlight = move_toward(_selected_highlight, 0.0, delta / 0.5)


func _insert_frame():
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Insert Keyframe")
	for layer in editing_node.layers:
		if editing_node.current_frame >= layer.frame_count:
			continue
		if selected_keyframe and layer != selected_keyframe.get_layer():
			continue
		undo_redo.add_do_method(layer, "insert_frame", editing_node.current_frame)
		undo_redo.add_undo_method(layer, "remove_frame", editing_node.current_frame)
	
	undo_redo.add_do_method(editing_node, "_update_frame_count")
	undo_redo.add_undo_method(editing_node, "_update_frame_count")
	
	undo_redo.add_do_method(editing_node, "goto", editing_node.current_frame + 1)
	undo_redo.add_undo_method(editing_node, "goto", editing_node.current_frame)
	
	undo_redo.commit_action()


func _remove_frame():
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Remove Frame")
	
	for layer: BrushLayer2D in editing_node.layers:
		if editing_node.current_frame >= layer.frame_count:
			continue
		if selected_keyframe and layer != selected_keyframe.get_layer():
			continue
		undo_redo.add_do_method(layer, "remove_frame", editing_node.current_frame)
		var keyframe = layer.get_keyframe(editing_node.current_frame)
		if keyframe:
			undo_redo.add_undo_method(layer, "insert_frame", editing_node.current_frame-1)
			undo_redo.add_undo_method(layer, "set_keyframe", keyframe, editing_node.current_frame)
		else:
			undo_redo.add_undo_method(layer, "insert_frame", editing_node.current_frame)
	undo_redo.add_do_method(editing_node, "_update_frame_count")
	undo_redo.add_undo_method(editing_node, "_update_frame_count")
	
	var max_frame = selected_keyframe.get_layer().frame_count - 1 if selected_keyframe else editing_node.frame_count - 1
	
	if editing_node.current_frame >= max_frame:
		undo_redo.add_do_method(editing_node, "goto", editing_node.current_frame - 1)
		undo_redo.add_undo_method(editing_node, "goto", editing_node.current_frame)
	
	undo_redo.commit_action()


func _convert_keyframe():
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Convert Keyframe")
	
	var layer = _get_current_layer()
	if not layer.is_keyframe(editing_node.current_frame):
		## Current frame is empty, insert a keyframe
		
		var copy = layer.get_frame(min(editing_node.current_frame, layer.frame_count-1)).duplicate()
		undo_redo.add_do_method(layer, "set_keyframe", copy, editing_node.current_frame)
		undo_redo.add_undo_method(layer, "remove_keyframe", editing_node.current_frame)
		
		if layer.frame_count < editing_node.current_frame:
			undo_redo.add_do_property(layer, "frame_count", editing_node.current_frame)
			undo_redo.add_undo_property(layer, "frame_count", layer.frame_count)
		
		undo_redo.add_do_method(editing_node, "_update_frame_count")
		undo_redo.add_undo_method(editing_node, "_update_frame_count")
	elif not layer.is_keyframe(editing_node.current_frame + 1):
		## Current frame is a keyframe, add a keyframe to the next frame
		var copy = layer.get_frame(editing_node.current_frame).duplicate()
		undo_redo.add_do_method(layer, "set_keyframe", copy, editing_node.current_frame + 1)
		undo_redo.add_undo_method(layer, "remove_frame", editing_node.current_frame + 1)
		
		undo_redo.add_do_method(editing_node, "_update_frame_count")
		undo_redo.add_undo_method(editing_node, "_update_frame_count")
		
		undo_redo.add_do_method(editing_node, "goto", editing_node.current_frame + 1)
		undo_redo.add_undo_method(editing_node, "goto", editing_node.current_frame)
	else:
		## Current and next frames are a keyframes, only move a frame forward
		undo_redo.add_do_method(editing_node, "goto", editing_node.current_frame + 1)
		undo_redo.add_undo_method(editing_node, "goto", editing_node.current_frame)
	
	undo_redo.commit_action()


func _convert_keyframe_blank():
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Convert Blank Keyframe")
	
	var layer: BrushLayer2D = _get_current_layer()
	if not layer.is_keyframe(editing_node.current_frame):
		var frame = BrushKeyframe2D.new()
		undo_redo.add_do_method(layer, "set_keyframe", frame, editing_node.current_frame)
		undo_redo.add_undo_method(layer, "remove_keyframe", editing_node.current_frame)
		
		undo_redo.add_do_method(editing_node, "_update_frame_count")
		undo_redo.add_undo_method(editing_node, "_update_frame_count")
		
		undo_redo.add_do_method(editing_node, "goto", editing_node.current_frame)
		undo_redo.add_undo_method(editing_node, "goto", editing_node.current_frame)
	elif not layer.is_keyframe(editing_node.current_frame + 1):
		var frame = BrushKeyframe2D.new()
		undo_redo.add_do_method(layer, "set_keyframe", frame, editing_node.current_frame + 1)
		undo_redo.add_undo_method(layer, "remove_frame", editing_node.current_frame + 1)
		
		undo_redo.add_do_method(editing_node, "_update_frame_count")
		undo_redo.add_undo_method(editing_node, "_update_frame_count")
		
		undo_redo.add_do_method(editing_node, "goto", editing_node.current_frame + 1)
		undo_redo.add_undo_method(editing_node, "goto", editing_node.current_frame)
	else:
		undo_redo.add_do_method(editing_node, "goto", editing_node.current_frame + 1)
		undo_redo.add_undo_method(editing_node, "goto", editing_node.current_frame)
	
	undo_redo.commit_action()


func _remove_keyframe():
	var layer: BrushLayer2D = _get_current_layer()
	var keyframe = layer.get_keyframe(editing_node.current_frame)
	if keyframe:
		var undo_redo = get_undo_redo()
		undo_redo.create_action("Remove Keyframe")
		undo_redo.add_do_method(layer, "remove_keyframe", editing_node.current_frame)
		undo_redo.add_undo_method(layer, "set_keyframe", keyframe, editing_node.current_frame)
		
		undo_redo.add_do_method(editing_node, "goto", editing_node.current_frame)
		undo_redo.add_undo_method(editing_node, "goto", editing_node.current_frame)
		
		undo_redo.commit_action()


static func set_tool(tool):
	editor._set_tool(tool)
	hud.select_tool(tool)


func _set_tool(tool):
	current_tool = tool
	if not button_select_mode.button_pressed:
		button_select_mode.emit_signal("pressed")


static func set_erase_mode(value):
	erase_mode = value
	hud.set_erase_mode(value)


static func set_paint_mode(paint_mode):
	editor.current_paint_mode = paint_mode
	hud.set_paint_mode(paint_mode)


static func set_warp_ease(warp_ease):
	editor.current_warp_ease = warp_ease
	hud.set_warp_ease(warp_ease)


func _action_start(mouse_position) -> bool:
	match _get_current_tool():
		TOOL_SELECT:
			if action_warp_try(mouse_position):
				return true
			return action_move_try(mouse_position)
		TOOL_PAINT:
			action_paint_start(mouse_position)
			return true
		TOOL_FILL:
			action_fill_try(mouse_position)
			return true
		TOOL_EYEDROPPER:
			for stroke: BrushStroke in _editing_brush.strokes:
				if stroke.is_point_inside(mouse_position):
					current_color = stroke.color
					hud._update_color_picker_color()
			return true
		TOOL_OVAL:
			action_oval_start(mouse_position)
			return true
		TOOL_RECT:
			action_rect_start(mouse_position)
			return true
		TOOL_SHAPE:
			action_shape_start(mouse_position)
			return true
		TOOL_SMOOTH:
			action_smooth_start(mouse_position)
			return true
	return false


func _current_action_complete(mouse_position):
	match _current_action:
		ACTION_WARP:
			action_warp_complete()
		ACTION_PAINT:
			action_paint_complete()
			hud._update_used_colors()
		ACTION_MOVE:
			action_move_complete()
		ACTION_OVAL:
			action_oval_complete(mouse_position)
		ACTION_RECT:
			action_rect_complete(mouse_position)
		ACTION_SHAPE:
			action_shape_complete()
	_current_action = ACTION_NONE


func _forward_draw_brush(brush: Brush2D):
	var cursor_position = brush.get_local_mouse_position()
	
	match _current_action:
		ACTION_OVAL:
			_action_oval_draw(brush)
			return
		ACTION_RECT:
			_action_rect_draw(brush)
			return
		ACTION_WARP:
			_action_warp_draw(brush)
			return
		ACTION_SHAPE:
			_action_shape_draw(brush)
			return
	
	match current_tool:
		TOOL_SELECT:
			if _current_action == ACTION_NONE:
				var zoom = _get_brush_zoom()
				for selection in edge_selections:
					_draw_warp_selection(selection)
					brush.draw_circle(selection.closest_point, 5.0 / zoom, Color.WHITE)
					_draw_circle_outline(brush, selection.closest_point, 8.0 / zoom, Color.WHITE, 1.0 / zoom)
					
					_draw_circle_outline(brush, selection.closest_point, _action_warp_size, Color(0.0, 0.0, 0.0, 0.2), 0.5 / zoom)
					_draw_circle_outline(brush, selection.closest_point, _action_warp_size, Color(1.0, 1.0, 1.0, 0.3), 0.5 / zoom)
		TOOL_SMOOTH:
			var zoom = _get_brush_zoom()
			for selection in edge_selections:
				_draw_warp_selection(selection)
				brush.draw_circle(selection.closest_point, 5.0 / zoom, Color.WHITE)
				_draw_circle_outline(brush, selection.closest_point, 8.0 / zoom, Color.WHITE, 1.0 / zoom)
				
				_draw_circle_outline(brush, selection.closest_point, _action_warp_size, Color(0.0, 0.0, 0.0, 0.2), 0.5 / zoom)
				_draw_circle_outline(brush, selection.closest_point, _action_warp_size, Color(1.0, 1.0, 1.0, 0.3), 0.5 / zoom)
	
	if _selected_highlight > 0.0:
		draw_brush_highlight(brush)


func draw_brush_highlight(brush: Brush2D):
		if _selected_highlight > 0.6 and fmod(_selected_highlight / 0.3, 1.0) > 0.5:
			return
		var thickness = 2.0 / editing_node.global_scale.x
		for stroke: BrushStroke in brush.strokes:
			if stroke.polygon.size() < 3 or stroke._erasing:
				continue
			brush.draw_stroke_outline(stroke, thickness, godot_selection_color, ease(_selected_highlight, 0.2))


func _draw_warp_selection(selection: EdgeSelection):
	var zoom = _get_brush_zoom()
	var stroke = selection.stroke
	
	var polygon = stroke.polygon if selection.hole_id == -1 else stroke.holes[selection.hole_id]
	
	for i in selection.vertex_indices.size() - 1:
		var from = polygon[selection.vertex_indices[i]]
		var to = polygon[selection.vertex_indices[i + 1]]
		var thickness_from = selection.vertex_weights[i]
		var thickness_to = selection.vertex_weights[i+1]
		
		var steps := 3.0
		for j in steps:
			var t_from = j / steps
			var t_to = (j + 1) / steps
			var pos_from = lerp(from, to, t_from)
			var pos_to = lerp(from, to, t_to)
			var thickness = lerp(thickness_from, thickness_to, j / steps) * 3.0 / zoom
			_editing_brush.draw_line(pos_from, pos_to, Color.WHITE, thickness)
			_editing_brush.draw_line(pos_from, pos_to, Color(1.0, 1.0, 1.0, 0.5), thickness + 0.3 / zoom)


func _forward_draw_hud():
	if allow_custom_cursor and allow_hide_cursor:
		_draw_custom_cursor()


func _draw_custom_cursor():
	if not _editing_brush or Input.is_key_pressed(KEY_SPACE) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		return
	var zoom = _get_brush_zoom()
	
	var cursor_position = hud.get_local_mouse_position()
	match _get_current_tool():
		TOOL_PAINT:
			if not (_current_action == ACTION_PAINT and _action_rmb):
				var size = _action_paint_size * 0.5 * zoom
				_draw_circle_outline(hud, cursor_position, size - 1.0, Color.BLACK, 1.0)
				_draw_circle_outline(hud, cursor_position, size + 1.0, Color.WHITE, 1.0)
			else:
				var size = _action_paint_erase_size * 0.5 * zoom
				_draw_circle_outline(hud, cursor_position, size, Color.BLACK, 1.0, true)
			if not (_current_action == ACTION_PAINT and not _action_rmb):
				var size = _action_paint_erase_size * 0.5 * zoom
				_draw_circle_outline(hud, cursor_position, size - 1.0, Color.BLACK, 1.0, true)
				_draw_circle_outline(hud, cursor_position, size + 1.0, Color(1.0, 1.0, 1.0, 0.2), 1.0, true)
			
			hud.draw_circle(cursor_position, 2.0, Color.WHITE)
		TOOL_SELECT:
			if _action_warp_size_preview_t > 0.0 and edge_selections.size() == 0:
				var color = Color(1.0, 1.0, 1.0, ease(_action_warp_size_preview_t, 0.4) * 0.2)
				_draw_circle_outline(hud, cursor_position, _action_warp_size * zoom, color, 0.5)
		TOOL_EYEDROPPER:
			var preview_size := 20.0
			for stroke: BrushStroke in _editing_brush.strokes:
				if stroke.is_point_inside(_editing_brush.get_local_mouse_position()):
					hud.draw_circle(cursor_position, preview_size, stroke.color)
					_draw_circle_outline(hud, cursor_position, preview_size, Color.WHITE)
				hud.draw_texture(TextureEyedropper, cursor_position + Vector2(-8, -16))
		TOOL_FILL:
			hud.draw_texture(TextureFill, cursor_position)


func _draw_circle_outline(target, draw_position: Vector2, size: float, color: Color = Color.WHITE, width = 0.5, striped := false):
	var point_count := 72
	var points = []
	if striped:
		#TODO: turn this into 
		for i in point_count:
			if i % 8 < 5:
				continue
			var from = draw_position + Vector2.RIGHT.rotated(i / float(point_count) * TAU) * size
			var to = draw_position + Vector2.RIGHT.rotated((i + 1) / float(point_count) * TAU) * size
			target.draw_line(from, to, color, width, true)
	else:
		for i in point_count:
			points.push_back(draw_position + Vector2.RIGHT.rotated(i / float(point_count) * TAU) * size)
		points.push_back(points[0])
		target.draw_polyline(PackedVector2Array(points), color, width, true)


## Actions

#region Action Warp

var edge_selections: Array

func action_warp_try(action_position: Vector2) -> bool:
	_get_edge_selections(action_position, _action_warp_size, current_warp_ease)
	#var selections := []
	#for stroke in _editing_brush.strokes:
		#var selection = _get_warp_selection(stroke, action_position, _action_warp_size)
		#if selection:
			#selections.push_back(selection)
	
	#edge_selections = selections
	if edge_selections.size() > 0:
		for selection in edge_selections:
			_editing_brush.move_stroke_to_front(selection.stroke)
		undo_redo_strokes_start()
		_current_action = ACTION_WARP
		_action_position_previous = action_position
		return true
	return false


func action_warp_process(action_position):
	var move_delta = action_position - _action_position_previous
	_action_position_previous = action_position
	
	for selection: EdgeSelection in edge_selections:
		for i in selection.get_vertex_count():
			var index = selection.vertex_indices[i]
			var weight = selection.vertex_weights[i]
			if selection.hole_id == -1:
				selection.stroke.polygon[index] += move_delta * weight
			else:
				selection.stroke.holes[selection.hole_id][index] += move_delta * weight
			selection.stroke.draw()


func action_warp_complete():
	for selection: EdgeSelection in edge_selections:
		_editing_brush.merge_stroke(selection.stroke)
	for selection: EdgeSelection in edge_selections:
		selection.stroke.optimize()
	for selection: EdgeSelection in edge_selections:
		if Geometry2D.is_polygon_clockwise(selection.stroke.polygon):
			selection.stroke.polygon.reverse()
		var invert_fix_results = Geometry2D.offset_polygon(selection.stroke.polygon, -0.01, Geometry2D.JOIN_ROUND)
		
		var holes = selection.stroke.holes
		
		var i := 0
		var l := invert_fix_results.size()
		while i < l:
			var polygon = invert_fix_results[i]
			if Geometry2D.is_polygon_clockwise(polygon):
				holes.push_back(invert_fix_results[i])
				invert_fix_results.remove_at(i)
				l -= 1
			else:
				i += 1
		_editing_brush.remove_stroke(selection.stroke)
		for polygon in invert_fix_results:
			var stroke = BrushStroke.new(polygon, [], selection.stroke.color)
			for hole in holes:
				if stroke.is_polygon_overlapping(hole):
					stroke.holes.push_back(hole)
			_editing_brush.add_stroke(stroke)
	
	_editing_brush.edited.emit()
	if editing_node is BrushAnimation2D:
		editing_node.edited.emit()
	edge_selections = []
	undo_redo_strokes_complete("Warp Stroke")
	_action_rmb = false


func _get_edge_selections(mouse_position, range: float, ease_mode):
	edge_selections = []
	for stroke: BrushStroke in _editing_brush.strokes:
		var selection: EdgeSelection = _get_edge_selection(
				stroke, stroke.polygon, stroke.polygon_curve,
				mouse_position, range, ease_mode
			)
		if selection:
			edge_selections.push_back(selection)
		
		## Holes
		for i in stroke.holes.size():
			var selection_hole: EdgeSelection = _get_edge_selection(
					stroke, stroke.holes[i], stroke.hole_curves[i],
					mouse_position, range, ease_mode
				)
			if selection_hole:
				selection_hole.hole_id = i
				edge_selections.push_back(selection_hole)


func _action_warp_draw(brush):
	for selection: EdgeSelection in edge_selections:
		_draw_warp_selection(selection)
		if selection.hole_id == -1:
			brush.draw_polygon_outline(selection.stroke.polygon, 1.0 / _get_brush_zoom(), Color.WHITE, 0.5)
		else:
			brush.draw_polygon_outline(selection.stroke.holes[selection.hole_id], 1.0 / _get_brush_zoom(), Color.WHITE, 0.5)

#endregion

#region Action Move

var action_move_stroke: BrushStroke

func action_move_try(action_position: Vector2) -> bool:
	for stroke: BrushStroke in _editing_brush.strokes:
		if stroke.is_point_inside(action_position):
			undo_redo_strokes_start()
			action_move_stroke = stroke
			_editing_brush.move_stroke_to_front(action_move_stroke)
			_action_position_previous = action_position
			_current_action = ACTION_MOVE
			return true
	return true


func action_move_process(action_position: Vector2):
	action_move_stroke.translate(action_position - _action_position_previous)
	action_move_stroke.draw()
	_action_position_previous = action_position


func action_move_complete():
	_editing_brush.merge_stroke(action_move_stroke)
	action_move_stroke = null
	_editing_brush.edited.emit()
	if editing_node is BrushAnimation2D:
		editing_node.edited.emit()
	
	undo_redo_strokes_complete("Move Stroke")

#endregion

#region Action Fill

func action_fill_try(action_position: Vector2):
	if _action_rmb:
		var stroke = get_stroke_at_position(action_position)
		if stroke:
			undo_redo_strokes_start()
			_editing_brush.remove_stroke(stroke)
			_editing_brush.edited.emit()
			undo_redo_strokes_complete("Bucket Clear")
		return
	
	var stroke_under_mouse = get_stroke_at_position(action_position)
	if stroke_under_mouse:
		undo_redo_strokes_start()
		stroke_under_mouse.color = current_color
		_editing_brush.merge_stroke(stroke_under_mouse)
		undo_redo_strokes_complete("Bucket Fill Recolor")
		return
	var hole_filled := false
	undo_redo_strokes_start()
	for stroke: BrushStroke in _editing_brush.strokes:
		for i in stroke.holes.size():
			if Geometry2D.is_point_in_polygon(action_position, stroke.holes[i]):
				if stroke.color.to_html() == current_color.to_html():
					stroke.holes.remove_at(i)
					for stroke_inside in _editing_brush.strokes:
						if stroke == stroke_inside:
							continue
						stroke.subtract_stroke(stroke_inside)
				else:
					var polygon = stroke.holes[i].duplicate()
					polygon.reverse()
					var fill_stroke = BrushStroke.new(polygon, [], current_color)
					for stroke_inside in _editing_brush.strokes:
						fill_stroke.subtract_stroke(stroke_inside)
					_editing_brush.add_stroke(fill_stroke)
				stroke.draw()
				_editing_brush.edited.emit()
				hole_filled = true
	if hole_filled:
		undo_redo_strokes_complete("Bucket Fill Hole")

#endregion

#region Action Brush

var _action_paint_curve_points := []


func action_paint_start(action_position: Vector2):
	_current_action = ACTION_PAINT
	_action_position_previous = action_position
	undo_redo_strokes_start()
	
	var color = (
		ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color.WHITE)
	if _action_rmb else
		current_color
	)
	_action_stroke = BrushStroke.new([], [], color)
	if _action_rmb:
		_action_stroke._erasing = true
	_editing_brush.add_stroke(_action_stroke)
	
	if current_paint_mode == PAINT_MODE_INSIDE:
		_action_brush_inside = get_stroke_at_position(action_position)
	
	_action_paint_curve_points = []
	action_paint_process(action_position)


func action_paint_process(action_position: Vector2):
	var brush_size = _action_paint_erase_size if _action_rmb else _action_paint_size
	
	_action_paint_curve_points.push_back(action_position)
	
	var brush_polygon = Goolash.create_polygon_line(_action_position_previous, action_position, brush_size)
	_action_stroke.union_polygon(brush_polygon)
	_action_position_previous = action_position
	
	_action_stroke.draw()


func action_paint_complete():
	if _action_paint_curve_points.size() >= 4 and not _action_rmb:
		_editing_brush.remove_stroke(_action_stroke)
		_action_stroke = BrushStroke.new([], [], current_color)
		
		var curve_catmull_rom = catmull_rom_interpolate(_action_paint_curve_points)
		for i in range(1, curve_catmull_rom.size()):
			var brush_size = _action_paint_erase_size if _action_rmb else _action_paint_size
			var brush_polygon = Goolash.create_polygon_line(curve_catmull_rom[i-1], curve_catmull_rom[i], brush_size)
			_action_stroke.union_polygon(brush_polygon)
	
	_action_stroke.optimize()
	
	if _action_rmb:
		_editing_brush.subtract_stroke(_action_stroke)
		undo_redo_strokes_complete("Paint Brush Erase")
	else:
		if _action_brush_inside:
			_editing_brush.remove_stroke(_action_stroke)
			var masked_strokes = _action_stroke.mask_stroke(_action_brush_inside)
			for stroke in masked_strokes:
				stroke.polygon = Geometry2D.offset_polygon(stroke.polygon, 0.01)[0]
				_editing_brush.merge_stroke(stroke)
			_action_brush_inside = null
		elif current_paint_mode == PAINT_MODE_INSIDE or current_paint_mode == PAINT_MODE_BEHIND:
			_editing_brush.move_stroke_to_back(_action_stroke)
			
			_editing_brush.edited.emit()
		else:
			_editing_brush.merge_stroke(_action_stroke)
		undo_redo_strokes_complete("Paint Brush Draw")
	_editing_brush.edited.emit()
	if editing_node is BrushAnimation2D:
		editing_node.edited.emit()


func catmull_rom_interpolate(points) -> PackedVector2Array:
	if points.size() < 4:
		return PackedVector2Array(points)
	
	var interpolated_points = PackedVector2Array()
	
	interpolated_points.append(points[0])
	
	for i in range(points.size() - 3):
		var p0 = points[i]
		var p1 = points[i + 1]
		var p2 = points[i + 2]
		var p3 = points[i + 3]
		
		var num_segments = min(ceil(p1.distance_to(p2) / 10.0), 8)
		for j in range(num_segments):
			var t = j / float(num_segments)
			var t2 = t * t
			var t3 = t2 * t
			
			var v = 0.5 * (
				(2.0 * p1) +
				(-p0 + p2) * t +
				(2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
				(-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
			)
			
			interpolated_points.append(v)
	
	return interpolated_points


#endregion

#region Action Oval

func action_oval_start(action_position):
	_current_action = ACTION_OVAL
	_action_position_previous = action_position
	
	undo_redo_strokes_start()


func _action_oval_draw(brush):
	var polygon = get_oval_tool_shape(
			_action_position_previous,
			brush.get_local_mouse_position(),
			Input.is_key_pressed(KEY_SHIFT),
			Input.is_key_pressed(KEY_ALT),
			0.0
	)
	
	var color = (
			_get_erase_color()
		if _action_rmb else
			current_color
	)
	brush.draw_polygon(polygon, [color])


func action_oval_complete(action_position):
	var polygon = get_oval_tool_shape(
			_action_position_previous,
			_editing_brush.get_local_mouse_position(),
			Input.is_key_pressed(KEY_SHIFT),
			Input.is_key_pressed(KEY_ALT)
	)
	var stroke := BrushStroke.new(polygon, [], current_color)
	
	if _action_rmb:
		_editing_brush.subtract_stroke(stroke)
		undo_redo_strokes_complete("Oval Brush Erase")
	else:
		_editing_brush.merge_stroke(stroke)
		undo_redo_strokes_complete("Oval Brush Draw")


func get_oval_tool_shape(from: Vector2, to: Vector2, centered: bool, equal: bool, noise := 0.03):
	var center: Vector2
	var size: Vector2 = (to - from) * 0.5
	if Input.is_key_pressed(KEY_ALT):
		center = from
		if Input.is_key_pressed(KEY_SHIFT):
			size = Vector2.ONE * max(abs(size.x), abs(size.y))
		size *= 2.0
	elif Input.is_key_pressed(KEY_SHIFT):
		var max_size = max(abs(size.x), abs(size.y))
		size = max_size * sign(size)
		center = from + size
	else:
		center = (from + to) * 0.5
	return create_oval_polygon(center, size, noise)


func create_oval_polygon(center: Vector2, size: Vector2, noise := 0.05) -> PackedVector2Array:
	var polygon := []
	if noise > 0.0:
		for i in 36.0:
			var noise_offset = Vector2.from_angle(randf() * TAU) * randf() * noise * size
			polygon.push_back(center + Vector2.from_angle(i / 36.0 * TAU) * size + noise_offset)
	else:
		for i in 36.0:
			polygon.push_back(center + Vector2.from_angle(i / 36.0 * TAU) * size)
	return PackedVector2Array(polygon)

#endregion

#region Action Rect

func action_rect_start(action_position):
	_current_action = ACTION_RECT
	_action_position_previous = action_position
	undo_redo_strokes_start()


func _action_rect_draw(brush):
	var polygon = get_rect_tool_shape(
			_action_position_previous,
			brush.get_local_mouse_position(),
			Input.is_key_pressed(KEY_SHIFT),
			Input.is_key_pressed(KEY_ALT),
			0.0
	)
	
	var color = (
		ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color.WHITE)
	if _action_rmb else
		current_color
	)
	brush.draw_polygon(polygon, [color])


func action_rect_complete(action_position):
	var polygon = get_rect_tool_shape(
			_action_position_previous,
			_editing_brush.get_local_mouse_position(),
			Input.is_key_pressed(KEY_SHIFT),
			Input.is_key_pressed(KEY_ALT)
	)
	var stroke := BrushStroke.new(polygon, [], current_color)
	
	if _action_rmb:
		_editing_brush.subtract_stroke(stroke)
		undo_redo_strokes_complete("Rect Brush Erase")
	else:
		_editing_brush.merge_stroke(stroke)
		undo_redo_strokes_complete("Rect Brush Draw")


func get_rect_tool_shape(from: Vector2, to: Vector2, centered: bool, equal: bool, noise := 0.01):
	var center: Vector2
	var size: Vector2 = (to - from) * 0.5
	if Input.is_key_pressed(KEY_ALT):
		center = from
		if Input.is_key_pressed(KEY_SHIFT):
			size = Vector2.ONE * max(abs(size.x), abs(size.y))
		size *= 2.0
	elif Input.is_key_pressed(KEY_SHIFT):
		var max_size = max(abs(size.x), abs(size.y))
		size = max_size * sign(size)
		center = from + size
	else:
		center = (from + to) * 0.5
	return create_rect_polygon(center, size, noise)


func create_rect_polygon(center: Vector2, size: Vector2, noise := 0.01) -> PackedVector2Array:
	var polygon := []
	var vertices_per_side := 10 if noise > 0.0 else 1
	var tl = center + size * Vector2(-1, -1)
	var tr = center + size * Vector2(1, -1)
	var br = center + size * Vector2(1, 1)
	var bl = center + size * Vector2(-1, 1)
	polygon.append_array(create_line_polygon(tl, tr, vertices_per_side, noise * size))
	polygon.append_array(create_line_polygon(tr, br, vertices_per_side, noise * size))
	polygon.append_array(create_line_polygon(br, bl, vertices_per_side, noise * size))
	polygon.append_array(create_line_polygon(bl, tl, vertices_per_side, noise * size))
	return PackedVector2Array(polygon)


func create_line_polygon(from, to, vertices_per_side, noise: Vector2):
	var polygon = []
	for i in vertices_per_side:
		var noise_offset = Vector2.from_angle(randf() * TAU) * randf() * noise
		var t = i / float(vertices_per_side)
		polygon.push_back(from.lerp(to, t) + noise_offset)
	return polygon

#endregion

#region Action Shape

func action_shape_start(action_position):
	undo_redo_strokes_start()
	
	_current_action = ACTION_SHAPE
	_action_position_previous = action_position
	
	var color = (
		ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color.WHITE)
	if _action_rmb else
		current_color
	)
	_action_stroke = BrushStroke.new([], [], color)
	if _action_rmb:
		_action_stroke._erasing = true
	_editing_brush.add_stroke(_action_stroke)


func _action_shape_draw(brush):
	var color = Color.RED if _action_rmb else lerp(current_color, Color.WHITE, 0.5)
	brush.draw_stroke_outline(_action_stroke, 1.0, color, 0.5)


func action_shape_process(action_position):
	#if Input.is_key_pressed(KEY_SHIFT) and _action_stroke.polygon.size() > 0:
		#_action_stroke.polygon[_action_stroke.polygon.size() - 1] = action_position
		#_action_stroke.draw()
		#return
	
	_action_stroke.polygon.push_back(action_position)
	_action_stroke.draw()


func action_shape_complete():
	if _action_rmb:
		_editing_brush.subtract_stroke(_action_stroke)
		undo_redo_strokes_complete("Shape Brush Erase")
	else:
		_editing_brush.merge_stroke(_action_stroke)
		undo_redo_strokes_complete("Shape Brush Draw")

#endregion

#region Action Smooth

func action_smooth_start(action_position):
	_current_action = ACTION_SMOOTH
	_update_smooth_region()


func action_smooth_mouse_motion(action_position):
	_update_smooth_region()


func _action_smooth_process(delta):
	for selection: EdgeSelection in edge_selections:
		var stroke = selection.stroke
		for i in selection.vertex_indices:
			if selection.hole_id == -1:
				stroke.polygon[i] = _smooth_polygon_point(stroke.polygon, i, delta)
			else:
				stroke.holes[selection.hole_id][i] = _smooth_polygon_point(stroke.holes[selection.hole_id], i, delta)
		stroke.draw()


func _smooth_polygon_point(polygon: PackedVector2Array, i: int, delta: float):
	var current = polygon[i]
	var before = polygon[(i - 1) % polygon.size()]
	var after = polygon[(i + 1) % polygon.size()]
	
	var angle_before = current.angle_to_point(before)
	var angle_after = current.angle_to_point(after)
	var angle = angle_difference(angle_before, angle_after)
	
	if angle < PI * 0.7:
		return current
	else:
		return lerp(current, lerp(before, after, 0.5), delta)


func _update_smooth_region():
	_get_edge_selections(_editing_brush.get_local_mouse_position(), 100.0, WARP_EASE_SMOOTH)


#endregion


## Get

func _get_editing_brush():
	if not editing_node:
		_editing_brush.edited.disconnect(_editing_brush_edited)
		_editing_brush = null
	elif editing_node is BrushAnimation2D:
		_editing_brush = editing_node.layers[editing_node._editing_layer_num].get_frame(editing_node.current_frame)
	elif editing_node is BrushClip3D:
		_editing_brush = editing_node.brush_animation2d.layers[editing_node._editing_layer_num].get_frame(editing_node.current_frame)
	elif editing_node is Brush3D:
		_editing_brush = editing_node.brush2d
	else:
		_editing_brush = editing_node
	
	if _editing_brush:
		_editing_brush.edited.connect(_editing_brush_edited)


func _get_current_layer():
	return editing_node.layers[editing_node._editing_layer_num]


func _get_current_tool() -> int:
	if current_tool_override != -1:
		return current_tool_override
	return current_tool


func _get_brush_zoom() -> float:
	if not is_instance_valid(editing_node):
		return 1.0
	return editing_node.get_viewport().get_screen_transform().get_scale().x


func _get_erase_color() -> Color:
	return ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color.WHITE)


func get_stroke_at_position(action_position, brush = null):
	if brush == null:
		brush = _editing_brush
	for stroke: BrushStroke in brush.strokes:
		if stroke.is_point_inside(action_position):
			return stroke
	return null


## 

#region Edge Select

func _get_edge_selection(stroke, polygon, curve, action_position: Vector2, range: float, ease_mode) -> EdgeSelection:
	if _action_rmb:
		var selection := EdgeSelection.new(stroke)
		var l = polygon.size()
		for i in l:
			var distance = polygon[i].distance_to(action_position)
			if distance < range:
				var t = 1.0 - distance / range
				var weight = _warp_ease(t, ease_mode)
				selection.add_vertex(i, weight)
		if selection.get_vertex_count() > 0:
			return selection
		return null
	
	var closest_point_on_edge = curve.get_closest_point(action_position)
	var distance_to_edge = closest_point_on_edge.distance_to(action_position)
	
	if distance_to_edge > 6.0 / _get_brush_zoom():
		return null
	
	var l = polygon.size()
	var closest_vertex_i: int = -1
	var closest_distance: float = 999.0
	for vertex_i in l:
		var dist = closest_point_on_edge.distance_to(polygon[vertex_i])
		if dist < closest_distance:
			closest_distance = dist
			closest_vertex_i = vertex_i
	
	var selection := EdgeSelection.new(stroke)
	
	selection.add_vertex(closest_vertex_i, 1.0)
	
	## travel clockwise of dragging point 👉
	var total_dist := 0.0
	for i in int(l * 0.5):
		var vertex_i = (closest_vertex_i + i + 1) % l
		var vertex_i_prev = (closest_vertex_i + i) % l
		#var vertex_i_next = (closest_vertex_i + i + 1) % l
		
		#var angle_prev = polygon[vertex_i_prev].angle_to_point(polygon[vertex_i])
		#var angle_next = polygon[vertex_i].angle_to_point(polygon[vertex_i_next])
		#if (angle_difference(angle_prev, angle_next)) > _action_warp_cut_angle:
			#break
		
		var dist = polygon[vertex_i].distance_to(polygon[vertex_i_prev])
		
		total_dist += dist
		if total_dist > range:
			## passed range, stop looking ✋
			break
		
		var weight = 1.0 - (total_dist / range)
		weight = _warp_ease(weight, ease_mode)
		selection.add_vertex(vertex_i, weight)
	
	## this is just so the preview line can be drawn in a straight line
	selection.vertex_indices.reverse()
	selection.vertex_weights.reverse()
	
	## travel counterclockwise of dragging point 👈
	total_dist = 0.0
	for i in int(l * 0.5):
		var vertex_i = (closest_vertex_i - i - 1 + l) % l
		var vertex_i_prev = (closest_vertex_i - i + l) % l
		#var vertex_i_next = (closest_vertex_i + l - i + 1) % l
		
		#var angle_prev = polygon[vertex_i_prev].angle_to_point(polygon[vertex_i])
		#var angle_next = polygon[vertex_i].angle_to_point(polygon[vertex_i_next])
		#if abs(angle_difference(angle_prev, angle_next)) > _action_warp_cut_angle:
			#break
		
		var dist = polygon[vertex_i].distance_to(polygon[vertex_i_prev])
		
		total_dist += dist
		if total_dist > range:
			## passed range, stop looking ✋
			break
		
		var weight = 1.0 - (total_dist / range)
		weight = _warp_ease(weight, ease_mode)
		selection.add_vertex(vertex_i, weight)
	
	selection.closest_point = closest_point_on_edge
	
	return selection



func _warp_ease(t, mode):
	match mode:
		WARP_EASE_SMOOTH:
			return ease(t, -1.5)
		WARP_EASE_SHARP:
			return ease(t, 3.0)
		WARP_EASE_LINEAR:
			return t
		WARP_EASE_RANDOM:
			return ease(t, -1.5) * randf()


class EdgeSelection:
	var stroke: BrushStroke
	var vertex_indices := []
	var vertex_weights := []
	var closest_point: Vector2
	
	var hole_id := -1
	
	func _init(stroke: BrushStroke):
		self.stroke = stroke
	
	
	func add_vertex(index: int, weight: float):
		var i = vertex_indices.find(index)
		if i != -1:
			## already has this vertex, use the heighest weight
			weight = max(vertex_weights[i], weight)
			return
		
		vertex_indices.push_back(index)
		vertex_weights.push_back(weight)
	
	func get_vertex_count() -> int:
		return vertex_indices.size()


#endregion

func _queue_redraw():
	hud.queue_redraw()
	if _editing_brush:
		_editing_brush._request_forward_draw()


func add_custom_script_to_keyframe(keyframe):
	if not keyframe.has_custom_script:
		keyframe.set_script(KEYFRAME_SCRIPT_CUSTOM.duplicate())
		keyframe.has_custom_script = true
		keyframe.edited.emit()
	EditorInterface.inspect_object(keyframe.get_script())


func _is_main_screen_visible(screen: int):
	return EditorInterface.get_editor_main_screen().get_child(screen).visible


static func is_editable(node):
	return node.scene_file_path == "" or node.get_tree().edited_scene_root == node


#region Layers

func set_editing_layer_num(value):
	if editing_node and editing_node is BrushAnimation2D:
		editing_node._editing_layer_num = value
		editing_layer_changed.emit()
		_get_editing_brush()


func get_editing_layer_num() -> int:
	if editing_node and editing_node is BrushAnimation2D:
		return editing_node._editing_layer_num
	return 0


func remove_layer(layer: BrushLayer2D):
	var clip = layer.get_clip()
	
	var undo_redo = get_undo_redo()
	undo_redo.create_action("Remove Layer")
	undo_redo.add_do_method(clip, "remove_layer", layer)
	undo_redo.add_undo_method(clip, "add_layer", layer)
	undo_redo.add_do_method(timeline, "_on_layer_added_or_removed")
	undo_redo.add_undo_method(timeline, "_on_layer_added_or_removed")
	
	undo_redo.add_do_method(self, "_get_editing_brush")
	undo_redo.add_undo_method(self, "_get_editing_brush")
	
	undo_redo.commit_action()


func create_layer():
	if not editing_node or not editing_node is BrushAnimation2D:
		return
	
	var layer = editing_node._create_layer()
	var undo_redo = get_undo_redo()
	undo_redo.create_action("New Layer")
	undo_redo.add_do_method(editing_node, "add_layer", layer)
	undo_redo.add_undo_method(editing_node, "remove_layer", layer)
	undo_redo.add_do_method(timeline, "_on_layer_added_or_removed")
	undo_redo.add_undo_method(timeline, "_on_layer_added_or_removed")
	undo_redo.commit_action()
	

#endregion


#region Undo/Redo

func undo_redo_strokes_start():
	_strokes_before = _editing_brush.get_strokes_duplicate()


func undo_redo_strokes_complete(name):
	var strokes_after = _editing_brush.get_strokes_duplicate()
	
	var undo_redo = get_undo_redo()
	undo_redo.create_action(name)
	undo_redo.add_undo_property(_editing_brush, "strokes", _strokes_before)
	undo_redo.add_do_property(_editing_brush, "strokes", strokes_after)
	undo_redo.add_do_method(_editing_brush, "redraw_all")
	undo_redo.add_undo_method(_editing_brush, "redraw_all")
	
	undo_redo.commit_action(false)

#endregion


#region Signals

func _editing_brush_edited():
	brush_edited.emit()

#endregion


#region Shader

func write_shader(anti_alias: bool, boiling: bool):
	var shader_source = "shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;\n
varying vec4 modulate;
"
	shader_source += "
uniform sampler2D goolash_boil_noise : repeat_enable;
uniform float goolash_frame;
"
	shader_source += "
void vertex() {
	modulate = COLOR;
}

void fragment() {
	COLOR.rgb = modulate.rgb;
	vec2 uv = SCREEN_UV;
	"
	
	if boiling:
		shader_source += "
	// Line boiling
	vec2 noise_uv = UV / 8.0;
	float frame = floor(goolash_frame / 4.0);
	noise_uv += vec2(frame * 0.05, frame * PI);
	uv += (texture(goolash_boil_noise, noise_uv).rg - 0.5) * 0.003;
	"
	
	if anti_alias:
		shader_source += "
	// Anti-alias
	float a = 0.0;
	float directions = 8.0;
	float quality = 4.0;
	float size = 4.0;
	for (float angle = 0.0; angle < TAU; angle += TAU / directions) {
		vec2 offset = vec2(cos(angle), sin(angle));
		for (float i = 1.0; i <= quality; i += 1.0) {
			a += texture(screen_texture, uv + offset * i / quality * size * SCREEN_PIXEL_SIZE).r;
		}
	}
	a /= directions * quality;
	a = smoothstep(0.3, 0.6, a);
	
	COLOR.a = a * modulate.a;
	"
	else:
		shader_source += "
	COLOR.a = texture(screen_texture, SCREEN_UV).r;
	"
	
	shader_source += "
}
"
	var file := FileAccess.open("res://addons/goolash/shading/brush_stroke.gdshader", FileAccess.WRITE)
	file.store_string(shader_source)
	file.close()

#endregion


static func douglas_peucker(points: PackedVector2Array, tolerance := 1.0) -> PackedVector2Array:
	if points.size() < 3:
		return points
	
	## Find the point with the maximum distance from the line between the first and last point
	var dmax := 0.0
	var index := 0
	for i in range(1, points.size() - 1):
		var d := 0.0
		var point = points[i]
		var point1 = points[0]
		var point2 = points[points.size() - 1]
		## Calculate the perpendicular distance between point and line segment point1-point2 
		var dx = point2.x - point1.x
		var dy = point2.y - point1.y
		
		if dx == 0 and dy == 0:
			## Point1 and point2 are the same point
			d = point1.distance_to(point)
		else:
			var t = ((point.x - point1.x) * dx + (point.y - point1.y) * dy) / (dx ** 2 + dy ** 2)
			if t < 0.0:
				## Point is beyond the 'left' end of the segment
				d = point.distance_to(point1)
			elif t > 1:
				### Point is beyond the 'right' end of the segment
				d = point.distance_to(point2)
			else:
				## Point is within the segment
				var point_t = Vector2(
						point1.x + t * dx,
						point1.y + t * dy
					)
				d = point.distance_to(point_t)
		
		if d > dmax:
			index = i
			dmax = d
	
	## If the maximum distance is greater than the tolerance, recursively simplify
	if dmax > tolerance:
		var results1 = douglas_peucker(points.slice(0, index+1), tolerance)
		var results2 = douglas_peucker(points.slice(index), tolerance)
		
		return results1 + results2.slice(1)
	else:
		return PackedVector2Array([points[0], points[points.size() - 1]])

