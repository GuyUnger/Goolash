@tool
class_name GoolashEditor extends EditorPlugin

signal selection_changed

enum {TOOL_SELECT, TOOL_PAINT, TOOL_FILL, TOOL_EYEDROPPER, TOOL_OVAL, TOOL_RECT, TOOL_SHAPE}
enum {ACTION_NONE, ACTION_WARP, ACTION_PAINT, ACTION_OVAL, ACTION_RECT, ACTION_SHAPE, ACTION_MOVE, ACTION_SELECT_RECT}

static var editor: GoolashEditor

const TextureEyedropper = preload("res://addons/goolash/icons/ColorPick.svg")
const TextureFill = preload("res://addons/goolash/icons/CursorBucket.svg")
const StrokeEraseMaterial = preload("res://addons/goolash/brush_erase_material.tres")
const StrokeRegularMaterial = preload("res://addons/goolash/brush_stroke_material.tres")

static var KEYFRAME_SCRIPT
static var KEYFRAME_SCRIPT_CUSTOM

var key_add_frame := KEY_5
var key_add_keyframe := KEY_6
var key_add_keyframe_blank := KEY_7
var key_add_script := KEY_9
var key_paint := KEY_B
var key_play := KEY_S
var key_frame_next := KEY_D
var key_frame_previous := KEY_A
var key_decrease := KEY_BRACKETLEFT
var key_increase := KEY_BRACKETRIGHT

static var hud
static var timeline

var _current_action: int
var _action_position_previous: Vector2
var _action_rmb := false
var _editing_layer_num: int: 
	get:
		if editing_node:
			return editing_node._editing_layer_num
		return 0
	set(value):
		if editing_node:
			editing_node._editing_layer_num = value
			selection_changed.emit()
var _action_paint_stroke: BrushStrokeData

var current_tool := -1
var current_tool_override := -1
var current_color: Color = Color.WHITE

var _action_paint_size := 10.0
var _action_paint_erase_size := 20.0
var _action_warp_size := 60.0

static var onion_skin_enabled := true
static var onion_skin_frames := 1

var editing_node
var selected_keyframe: BrushKeyframe2D
var is_editing := false

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
	
	_init_project_settings()
	_load_project_settings(true)
	
	add_custom_type("BrushClip2D", "Node2D", load("res://addons/goolash/brush_clip2d.gd"), null)
	
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
	
	hud.visible = is_editing
	EditorInterface.inspect_object(editing_node)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _init_project_settings():
	add_project_setting("goolash/animation/default_fps", 12)
	add_project_setting("goolash/animation/onion_skin_enabled", true)
	add_project_setting("goolash/animation/onion_skin_frames", 2)
	add_project_setting("goolash/painting/default_color", Color.PERU)
	add_project_setting("goolash/rendering/anti-alias", true)
	add_project_setting("goolash/rendering/boiling", true)


func add_project_setting(name: String, default_value) -> void:
	if ProjectSettings.has_setting(name):
		return
	ProjectSettings.set_setting(name, default_value)
	ProjectSettings.set_initial_value(name, default_value)


func _load_project_settings(init := false):
	Goolash.default_fps = ProjectSettings.get_setting_with_override("goolash/animation/default_fps")
	onion_skin_enabled = ProjectSettings.get_setting_with_override("goolash/animation/onion_skin_enabled")
	onion_skin_frames = ProjectSettings.get_setting_with_override("goolash/animation/onion_skin_frames")
	current_color = ProjectSettings.get_setting_with_override("goolash/painting/default_color")
	
	var shader_anti_alias_setting = ProjectSettings.get_setting_with_override("goolash/rendering/anti-alias")
	var shader_boil_setting = ProjectSettings.get_setting_with_override("goolash/rendering/boiling")
	if shader_anti_alias != shader_anti_alias_setting or shader_boil != shader_boil_setting:
		shader_anti_alias = shader_anti_alias_setting
		shader_boil = shader_boil_setting
		if not init:
			write_shader(shader_anti_alias, shader_boil)

func _on_settings_changed():
	_load_project_settings()


func _exit_tree() -> void:
	remove_custom_type("BrushClip2D")
	
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
	if not button_select_mode.button_pressed:
		return false
	if object is BrushClip2D or object is BrushKeyframe2D or object is Brush2D:
		return true
	return false


func _on_selection_changed():
	var selection := get_editor_interface().get_selection()
	var selected_nodes = selection.get_selected_nodes()
	selected_keyframe = null
	if selected_nodes.size() == 1:
		if selected_nodes[0] is BrushClip2D:
			select_brush_clip(selected_nodes[0])
			return
		elif selected_nodes[0] is BrushKeyframe2D:
			var frame: BrushKeyframe2D = selected_nodes[0]
			select_brush_clip(frame.get_clip())
			frame.get_clip().goto(frame.frame_num)
			selected_keyframe = frame
			return
		elif selected_nodes[0] is Brush2D:
			select_brush(selected_nodes[0])
			return
		elif selected_nodes[0] is BrushLayer2D:
			var layer: BrushLayer2D = selected_nodes[0]
			select_brush_clip(layer.get_clip())
			editing_node._editing_layer_num = layer.layer_num
	
	if editing_node:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		timeline.load_brush_clip(null)
		_edit_brush_complete()
	
	var visible_2d = EditorInterface.get_editor_main_screen().get_child(0).visible
	var visible_3d = EditorInterface.get_editor_main_screen().get_child(1).visible
	var visible_script = EditorInterface.get_editor_main_screen().get_child(2).visible
	if visible_script and (visible_2d or visible_3d):
		EditorInterface.get_editor_main_screen().get_child(2).visible = false


func select_brush(brush):
	_edit_start(brush)
	is_editing = button_select_mode.button_pressed


func select_brush_clip(clip):
	_edit_start(clip)
	timeline.load_brush_clip(clip)
	make_bottom_panel_item_visible(timeline)
	clip.draw()
	clip.init()
	is_editing = button_select_mode.button_pressed
	return


func _edit_start(node):
	editing_node = node
	var editing_brush = _get_editing_brush()
	editing_brush._selected_highlight = 1.0
	
	hud.visible = true
	hud._update_used_colors()
	set_process(is_editable(editing_node))


func _edit_brush_complete():
	var brush = _get_editing_brush()
	var i := 0
	while i < brush.stroke_data.size():
		var stroke: BrushStrokeData = brush.stroke_data[i]
		if stroke.polygon.size() < 4:
			brush.stroke_data.remove_at(i)
		else:
			i += 1
	
	var previous_editing = editing_node
	queue_redraw()
	editing_node = null
	previous_editing.draw()
	hud.visible = false
	set_process(false)


#region INPUT
func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not editing_node:
		return false
	
	if event is InputEventMouse:
		return _input_mouse(event)
	elif event is InputEventKey:
		if event.is_pressed():
			return _on_key_pressed(event)
	return false


func _on_key_pressed(event: InputEventKey) -> bool:
	if Input.is_key_pressed(KEY_CTRL):
		return false
	
	match event.keycode:
		KEY_ALT:
			_on_input_key_alt_pressed()
		key_play:
			if editing_node is BrushClip2D:
				if editing_node.is_playing:
					editing_node.stop()
				else:
					editing_node.play()
				return true
		key_frame_previous:
			if editing_node is BrushClip2D:
				editing_node.stop()
				if editing_node.previous_frame():
					return true
		key_frame_next:
			if editing_node is BrushClip2D:
				editing_node.stop()
				if editing_node.next_frame():
					return true
		KEY_Q:
			set_tool(GoolashEditor.TOOL_SELECT)
			return true
		key_paint:
			set_tool(GoolashEditor.TOOL_PAINT)
			return true
		KEY_M:
			set_tool(GoolashEditor.TOOL_RECT)
			return true
		KEY_G:
			set_tool(GoolashEditor.TOOL_FILL)
			return true
		KEY_O:
			set_tool(GoolashEditor.TOOL_OVAL)
			return true
		KEY_P:
			set_tool(GoolashEditor.TOOL_SHAPE)
			return true
		key_add_frame:
			if Input.is_key_pressed(KEY_SHIFT):
				_remove_frame()
			else:
				_insert_frame()
			return true
		key_add_keyframe:
			if Input.is_key_pressed(KEY_SHIFT):
				pass
			else:
				_convert_keyframe()
			return true
		key_add_keyframe_blank:
			if Input.is_key_pressed(KEY_SHIFT):
				pass
			else:
				_convert_keyframe_blank()
			return true
		key_add_script:
			if selected_keyframe:
				add_custom_script_to_keyframe(selected_keyframe)
				
		key_decrease:
			_action_paint_erase_size *= 1 / (2.0 ** (1.0 / 6.0))
			_action_paint_size *= 1 / (2.0 ** (1.0 / 6.0))
			return true
		key_increase:
			_action_paint_erase_size *= 2.0 ** (1.0 / 6.0)
			_action_paint_size *= 2.0 ** (1.0 / 6.0)
			
			return true
	return false



func _on_input_key_alt_pressed() -> bool:
	if current_tool == TOOL_PAINT or current_tool == TOOL_FILL:
		current_tool_override = TOOL_EYEDROPPER
		queue_redraw()
	return false



func _input_mouse(event: InputEventMouse) -> bool:
	var mouse_position = editing_node.get_local_mouse_position()
	if event is InputEventMouseButton:
		var event_mouse_button: InputEventMouseButton = event
		if event_mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if event_mouse_button.pressed:
				_on_lmb_pressed(mouse_position)
			else:
				_on_lmb_released()
		elif event_mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			if event_mouse_button.pressed:
				_on_rmb_pressed(mouse_position)
			else:
				_on_rmb_released()
	elif event is InputEventMouseMotion:
		_on_mouse_motion(mouse_position)
	return true


func _on_mouse_motion(mouse_position):
	queue_redraw()
	match _current_action:
		ACTION_WARP:
			action_warp_process(mouse_position)
		ACTION_SHAPE:
			action_shape_process(mouse_position)
		ACTION_PAINT:
			action_paint_process(mouse_position)
		ACTION_MOVE:
			action_move_process(mouse_position)


func _on_lmb_pressed(mouse_position: Vector2):
	if _current_action != ACTION_NONE:
		return
	_action_rmb = false
	_action_start(mouse_position, false)


func _on_rmb_pressed(mouse_position: Vector2):
	if _current_action != ACTION_NONE:
		return
	_action_rmb = true
	_action_start(mouse_position, true)


func _on_lmb_released():
	current_action_complete(editing_node.get_local_mouse_position())


func _on_rmb_released():
	current_action_complete(editing_node.get_local_mouse_position())


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
		queue_redraw()
	
	allow_hide_cursor = (
			EditorInterface.get_editor_main_screen().get_child(0).visible and
			hud.get_rect().has_point(hud.get_local_mouse_position()) and
			allow_custom_cursor and 
			DisplayServer.window_is_focused()
	)
	if (current_tool == TOOL_PAINT or current_tool == TOOL_FILL) and allow_hide_cursor:
		##todo: this needs more checks
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if current_tool == TOOL_RECT or current_tool == TOOL_OVAL:
			Input.set_default_cursor_shape(Input.CURSOR_CROSS)
			## this no work :(
		else:
			Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	
	if current_tool_override == TOOL_EYEDROPPER and not Input.is_key_pressed(KEY_ALT):
		current_tool_override = -1
		queue_redraw()


func _insert_frame():
	for layer in editing_node.layers:
		layer.insert_frame(editing_node.current_frame)
	editing_node.next_frame()
	editing_node._update_frame_count()


func _remove_frame():
	for layer in editing_node.layers:
		layer.remove_frame(editing_node.current_frame)
	editing_node.previous_frame()
	editing_node._update_frame_count()


func _convert_keyframe():
	var layer = _get_current_layer()
	if not layer.is_keyframe(editing_node.current_frame):
		var copy = layer.get_frame(editing_node.current_frame).duplicate()
		layer.set_keyframe(copy, editing_node.current_frame)
		editing_node._update_frame_count()
		return true
	elif not layer.is_keyframe(editing_node.current_frame + 1):
		var copy = layer.get_frame(editing_node.current_frame).duplicate()
		layer.set_keyframe(copy, editing_node.current_frame + 1)
		editing_node._update_frame_count()
		editing_node.next_frame()
	else:
		editing_node._update_frame_count()
		editing_node.next_frame()


func _convert_keyframe_blank():
	var layer = _get_current_layer()
	if not layer.is_keyframe(editing_node.current_frame):
		layer.set_keyframe(BrushKeyframe2D.new(), editing_node.current_frame)
		editing_node._update_frame_count()
		return true
	elif not layer.is_keyframe(editing_node.current_frame + 1):
		layer.set_keyframe(BrushKeyframe2D.new(), editing_node.current_frame + 1)
		editing_node._update_frame_count()
		editing_node.next_frame()
	else:
		editing_node._update_frame_count()
		editing_node.next_frame()


static func set_tool(tool):
	editor._set_tool(tool)
	hud.select_tool(tool)


func _set_tool(tool):
	current_tool = tool
	if not button_select_mode.button_pressed:
		button_select_mode.emit_signal("pressed")


func _action_start(mouse_position, alt):
	_action_rmb = alt
	match _get_current_tool():
		TOOL_SELECT:
			if action_warp_try(mouse_position):
				return
			action_move_try(mouse_position)
		TOOL_PAINT:
			action_paint_start(mouse_position)
		TOOL_FILL:
			action_fill_try(mouse_position)
		TOOL_EYEDROPPER:
			for stroke: BrushStrokeData in _get_editing_brush().stroke_data:
				if stroke.is_point_inside(mouse_position):
					current_color = stroke.color
					hud._update_color_picker_color()
		TOOL_OVAL:
			action_oval_start(mouse_position)
		TOOL_RECT:
			action_rect_start(mouse_position)
		TOOL_SHAPE:
			action_shape_start(mouse_position)


func current_action_complete(mouse_position):
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


func _forward_draw_brush(brush):
	
	var cursor_position = brush.get_local_mouse_position()
	
	match _current_action:
		ACTION_OVAL:
			action_oval_draw(brush)
			return
		ACTION_RECT:
			action_rect_draw(brush)
			return
	
	match current_tool:
		TOOL_SELECT:
			var zoom = _get_editing_brush().get_viewport().get_screen_transform().get_scale().x
			for stroke: BrushStrokeData in brush.stroke_data:
				if is_instance_valid(stroke) and _is_hovering_edge(stroke, cursor_position):
					brush.draw_polygon_outline(stroke.polygon, 1.0 / zoom)


func _forward_draw_hud():
	if allow_custom_cursor and allow_hide_cursor:
		_draw_custom_cursor()


func _draw_custom_cursor():
	if not _get_editing_brush():
		return
	var zoom = _get_editing_brush().get_viewport().get_screen_transform().get_scale().x
	
	var cursor_position = hud.get_local_mouse_position()
	match _get_current_tool():
		TOOL_PAINT:
			if not (_current_action == ACTION_PAINT and _action_rmb):
				_draw_circle_outline(hud, cursor_position, _action_paint_size * zoom, Color.BLACK, 1.0)
				_draw_circle_outline(hud, cursor_position, _action_paint_size * zoom + 2.0, Color.WHITE, 1.0)
			else:
				_draw_circle_outline(hud, cursor_position, _action_paint_erase_size * zoom, Color.BLACK, 1.0, true)
			if not (_current_action == ACTION_PAINT and not _action_rmb):
				_draw_circle_outline(hud, cursor_position, _action_paint_erase_size * zoom, Color.BLACK, 1.0, true)
				_draw_circle_outline(hud, cursor_position, _action_paint_erase_size * zoom, Color(1.0, 1.0, 1.0, 0.2), 1.0, true)
			
			hud.draw_circle(cursor_position, 2.0, Color.WHITE)
		TOOL_SELECT:
			pass
		TOOL_EYEDROPPER:
			var preview_size := 20.0
			for stroke: BrushStrokeData in _get_editing_brush().stroke_data:
				if stroke.is_point_inside(_get_editing_brush().get_local_mouse_position()):
					hud.draw_circle(cursor_position, preview_size, stroke.color)
					_draw_circle_outline(hud, cursor_position, preview_size, Color.WHITE)
				hud.draw_texture(TextureEyedropper, cursor_position + Vector2(-8, -16))
		TOOL_FILL:
			hud.draw_texture(TextureFill, cursor_position)


func _draw_circle_outline(target, draw_position: Vector2, size: float, color: Color = Color.WHITE, width = 0.5, striped := false):
	var point_count := 36
	for i in point_count:
		if striped and i % 4 < 3:
			continue
		var from = draw_position + Vector2.RIGHT.rotated(i / float(point_count) * TAU) * size
		var to = draw_position + Vector2.RIGHT.rotated((i + 1) / float(point_count) * TAU) * size
		target.draw_line(from, to, color, width, true)


## ACTIONS

#region ACTION WARP

var action_warp_selections := []

func action_warp_try(action_position: Vector2) -> bool:
	var brush = _get_editing_brush()
	
	for stroke in brush.stroke_data:
		_warp_stroke_try(stroke, action_position, _action_warp_size)
	if action_warp_selections.size() > 0:
		_current_action = ACTION_WARP
		_action_position_previous = action_position
		return true
	return false


func _warp_stroke_try(stroke: BrushStrokeData, action_postion: Vector2, range: float):
	var zoom: float = _get_editing_brush().get_viewport().get_screen_transform().get_scale().x
	var closest_vertex_i: int = -1
	var closest_distance: float = 10.0 / zoom
	
	var polygon = stroke.polygon
	var l = polygon.size()
	
	for vertex_i in l:
		var dist = action_postion.distance_to(polygon[vertex_i])
		if dist < closest_distance:
			closest_distance = dist
			closest_vertex_i = vertex_i
	
	if closest_vertex_i == -1:
		return
	
	undo_redo_strokes_start()
	
	var selection := ActionWarpSelection.new(stroke)
	action_warp_selections.push_back(selection)
	
	selection.add_vertex(closest_vertex_i, 1.0)
	
	## travel clockwise of dragging point 👉
	var total_dist := 0.0
	for i in int(l * 0.5) - 1:
		var vertex_i = (closest_vertex_i + i + 1) % l
		var vertex_i_prev = (closest_vertex_i + i) % l
		var dist = polygon[vertex_i].distance_to(polygon[vertex_i_prev])
		
		total_dist += dist
		if total_dist > range:
			## passed range, stop looking ✋
			break
		
		var weight = 1.0 - (total_dist / range)
		weight = _warp_ease(weight)
		selection.add_vertex(vertex_i, weight)
	
	## travel counterclockwise of dragging point 👈
	total_dist = 0.0
	for i in int(l * 0.5) - 1:
		var vertex_i = (closest_vertex_i - i - 1 + l) % l
		var vertex_i_prev = (closest_vertex_i - i + l) % l
		var dist = polygon[vertex_i].distance_to(polygon[vertex_i_prev])
		
		total_dist += dist
		if total_dist > range:
			## passed range, stop looking ✋
			break
		
		var weight = 1.0 - (total_dist / range)
		weight = _warp_ease(weight)
		selection.add_vertex(vertex_i, weight)


func _is_hovering_edge(stroke, mouse_position):
	var zoom = _get_editing_brush().get_viewport().get_screen_transform().get_scale().x
	
	var closest_point = stroke.polygon_curve.get_closest_point(mouse_position)
	return closest_point.distance_to(mouse_position) < 10.0 / zoom


func action_warp_process(action_position):
	var move_delta = action_position - _action_position_previous
	_action_position_previous = action_position
	
	for selection: ActionWarpSelection in action_warp_selections:
		for i in selection.vertex_count():
			var index = selection.vertex_indexes[i]
			var weight = selection.vertex_weights[i]
			selection.stroke.polygon[index] += move_delta * weight
	
	_get_editing_brush().draw()


func _warp_ease(t):
	if _action_rmb:
		return ease(t, 2.0)
	else:
		return ease(t, -1.5)


func action_warp_complete():
	for selection: ActionWarpSelection in action_warp_selections:
		merge_stroke(selection.stroke)
	for selection: ActionWarpSelection in action_warp_selections:
		selection.stroke.optimize()
	for selection: ActionWarpSelection in action_warp_selections:
		if Geometry2D.is_polygon_clockwise(selection.stroke.polygon):
			selection.stroke.polygon.reverse()
		var invert_fix_results = Geometry2D.offset_polygon(selection.stroke.polygon, 0.0, Geometry2D.JOIN_ROUND)
		
		var holes = selection.stroke.holes
		
		var i := 0
		while i < invert_fix_results.size():
			var polygon = invert_fix_results[i]
			if Geometry2D.is_polygon_clockwise(polygon):
				holes.push_back(invert_fix_results[i])
				invert_fix_results.remove_at(i)
			else:
				i += 1
		
		_get_editing_brush().stroke_data.erase(selection.stroke)
		for polygon in invert_fix_results:
			var stroke = BrushStrokeData.new(polygon, [], selection.stroke.color)
			for hole in holes:
				if stroke.is_polygon_overlapping(hole):
					stroke.holes.push_back(hole)
			_get_editing_brush().add_stroke(stroke)
	_get_editing_brush().draw()
	_get_editing_brush().edited.emit()
	if editing_node is BrushClip2D:
		editing_node.edited.emit()
	action_warp_selections = []
	undo_redo_strokes_complete("Warp Stroke")


class ActionWarpSelection:
	var stroke: BrushStrokeData
	var vertex_indexes := []
	var vertex_weights := []
	
	
	func _init(stroke: BrushStrokeData):
		self.stroke = stroke
	
	
	func add_vertex(index: int, weight: float):
		var i = vertex_indexes.find(index)
		if i != -1:
			## already has this vertex, use the heighest weight
			vertex_weights = max(vertex_weights[i], weight)
			return
		
		vertex_indexes.push_back(index)
		vertex_weights.push_back(weight)
	
	
	func vertex_count():
		return vertex_indexes.size()


class ActionWarpSelectionHole extends ActionWarpSelection:
	var hole_id := 0

#endregion


#region ACTION MOVE

var action_move_stroke

func action_move_try(action_position: Vector2) -> bool:
	for stroke: BrushStrokeData in _get_editing_brush().stroke_data:
		if stroke.is_point_inside(action_position):
			undo_redo_strokes_start()
			action_move_stroke = stroke
			_action_position_previous = action_position
			_current_action = ACTION_MOVE
			return true
	return false


func action_move_process(action_position: Vector2):
	action_move_stroke.translate(action_position - _action_position_previous)
	_action_position_previous = action_position
	_get_editing_brush().draw()


func action_move_complete():
	merge_stroke(action_move_stroke)
	action_move_stroke = null
	_get_editing_brush().edited.emit()
	if editing_node is BrushClip2D:
		editing_node.edited.emit()
	undo_redo_strokes_complete("Move Stroke")

#endregion


#region ACTION FILL

func action_fill_try(action_position: Vector2):
	var brush = _get_editing_brush()
	for stroke: BrushStrokeData in brush.stroke_data:
		if stroke.is_point_inside(action_position):
			undo_redo_strokes_start()
			stroke.color = current_color
			merge_stroke(stroke)
			undo_redo_strokes_complete("Bucket fill recolor")
			return
	for stroke: BrushStrokeData in brush.stroke_data:
		for i in stroke.holes.size():
			if Geometry2D.is_point_in_polygon(action_position, stroke.holes[i]):
				undo_redo_strokes_start()
				
				if stroke.color.to_html() == current_color.to_html():
					stroke.holes.remove_at(i)
				else:
					var polygon = stroke.holes[i].duplicate()
					polygon.reverse()
					var fill_stroke = BrushStrokeData.new(polygon, [], current_color)
					for stroke_inside in brush.stroke_data:
						fill_stroke = fill_stroke.subtract_stroke(stroke_inside)[0]
					brush.add_stroke(fill_stroke)
				brush.draw()
				brush.edited.emit()
				undo_redo_strokes_complete("Bucket fill hole")
				return

#endregion


#region ACTION BRUSH

func action_paint_start(action_position: Vector2):
	_current_action = ACTION_PAINT
	_action_position_previous = action_position
	undo_redo_strokes_start()
	
	var brush = _get_editing_brush()
	
	var color = (
		ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color.WHITE)
	if _action_rmb else
		current_color
	)
	_action_paint_stroke = BrushStrokeData.new([], [], color)
	if _action_rmb:
		_action_paint_stroke._erasing = true
	brush.add_stroke(_action_paint_stroke)
	
	action_paint_process(action_position)


func action_paint_complete():
	_action_paint_stroke.optimize()
	if _action_rmb:
		_action_brush_subtract_complete()
		_get_editing_brush().edited.emit()
	else:
		_action_brush_add_complete()
		_get_editing_brush().edited.emit()
	if editing_node is BrushClip2D:
		editing_node.edited.emit()


func _action_brush_add_complete():
	var brush = _get_editing_brush()
	
	var strokes := []
	while brush.stroke_data.size() > 0:
		var stroke = brush.stroke_data.pop_front()
		if stroke == _action_paint_stroke:
			continue
		if _action_paint_stroke.is_stroke_overlapping(stroke):
			if _action_paint_stroke.color == stroke.color:
				_action_paint_stroke.union_stroke(stroke)
			else:
				strokes.append_array(stroke.subtract_stroke(_action_paint_stroke))
		else:
			strokes.push_back(stroke)
	
	strokes.push_back(_action_paint_stroke)
	
	for stroke in strokes:
		brush.add_stroke(stroke)
	
	_action_paint_stroke = null
	brush.draw()
	brush.edited.emit()
	
	undo_redo_strokes_complete("Paint brush draw")

func _action_brush_subtract_complete():
	var brush = _get_editing_brush()
	
	var strokes := []
	brush.stroke_data.erase(_action_paint_stroke)
	while _get_editing_brush().stroke_data.size() > 0:
		var stroke: BrushStrokeData = brush.stroke_data.pop_front()
		strokes.append_array(stroke.subtract_stroke(_action_paint_stroke))
	
	for stroke in strokes:
		brush.add_stroke(stroke)
	
	_action_paint_stroke = null
	brush.draw()
	brush.edited.emit()
	
	undo_redo_strokes_complete("Paint brush erase")


func action_paint_process(action_position: Vector2):
	var brush_size = _action_paint_erase_size if _action_rmb else _action_paint_size
	var brush_polygon = _create_polygon_circle(_action_position_previous, action_position, brush_size)
	_action_paint_stroke.union_polygon(brush_polygon)
	_action_position_previous = action_position
	_get_editing_brush().draw()


func _create_polygon_circle(start_position: Vector2, end_position: Vector2, size: float) -> PackedVector2Array:
	var angle = start_position.angle_to_point(end_position)
	var brush_polygon = []
	var points := 16.0
	for i in points:
		brush_polygon.push_back(start_position + Vector2.DOWN.rotated(angle + i / points * PI) * size)
	for i in points:
		brush_polygon.push_back(end_position + Vector2.DOWN.rotated(angle + PI + i / points * PI) * size)
	return PackedVector2Array(brush_polygon)

#endregion


#region ACTION OVAL

func action_oval_start(action_position):
	_current_action = ACTION_OVAL
	_action_position_previous = action_position
	
	undo_redo_strokes_start()


func action_oval_draw(brush):
	var polygon = get_oval_tool_shape(
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


func action_oval_complete(action_position):
	var brush = _get_editing_brush()
	var polygon = get_oval_tool_shape(
			_action_position_previous,
			brush.get_local_mouse_position(),
			Input.is_key_pressed(KEY_SHIFT),
			Input.is_key_pressed(KEY_ALT)
	)
	var stroke := BrushStrokeData.new(polygon, [], current_color)
	
	if _action_rmb:
		subtract_stroke(stroke)
		undo_redo_strokes_complete("Oval brush erase")
	else:
		merge_stroke(stroke)
		undo_redo_strokes_complete("Oval brush draw")
	


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


#region ACTION RECT

func action_rect_start(action_position):
	_current_action = ACTION_RECT
	_action_position_previous = action_position
	undo_redo_strokes_start()


func action_rect_draw(brush):
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
	var brush = _get_editing_brush()
	var polygon = get_rect_tool_shape(
			_action_position_previous,
			brush.get_local_mouse_position(),
			Input.is_key_pressed(KEY_SHIFT),
			Input.is_key_pressed(KEY_ALT)
	)
	var stroke := BrushStrokeData.new(polygon, [], current_color)
	
	if _action_rmb:
		subtract_stroke(stroke)
		undo_redo_strokes_complete("Rect brush erase")
	else:
		merge_stroke(stroke)
		undo_redo_strokes_complete("Rect brush draw")


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


#region ACTION SHAPE

func action_shape_start(action_position):
	undo_redo_strokes_start()
	
	_current_action = ACTION_SHAPE
	_action_position_previous = action_position
	
	var color = (
		ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color", Color.WHITE)
	if _action_rmb else
		current_color
	)
	_action_paint_stroke = BrushStrokeData.new([], [], color)
	if _action_rmb:
		_action_paint_stroke._erasing = true
	_get_editing_brush().add_stroke(_action_paint_stroke)

func action_shape_process(action_position):
	if Input.is_key_pressed(KEY_ALT) and _action_paint_stroke.polygon.size() > 0:
		_action_paint_stroke.polygon[_action_paint_stroke.polygon.size() - 1] = action_position
		_get_editing_brush().draw()
		return
	
	_action_paint_stroke.polygon.push_back(action_position)
	_get_editing_brush().draw()


func action_shape_complete():
	if _action_rmb:
		_action_brush_subtract_complete()
		undo_redo_strokes_complete("Shape brush erase")
	else:
		_action_brush_add_complete()
		undo_redo_strokes_complete("Shape brush draw")

#endregion


func merge_stroke(stroke):
	_action_paint_stroke = stroke
	_action_brush_add_complete()


func subtract_stroke(stroke):
	_action_paint_stroke = stroke
	_action_brush_subtract_complete()


func _get_editing_brush() -> Brush2D:
	if editing_node is BrushClip2D:
		return editing_node.layers[_editing_layer_num].get_frame(editing_node.current_frame)
	else:
		return editing_node


func _get_current_layer():
	return editing_node.layers[_editing_layer_num]


func _get_current_tool() -> int:
	if current_tool_override != -1:
		return current_tool_override
	return current_tool


func queue_redraw():
	hud.queue_redraw()
	if _get_editing_brush():
		_get_editing_brush()._forward_draw_requested = true
		_get_editing_brush().queue_redraw()


func add_custom_script_to_keyframe(keyframe):
	if keyframe.has_custom_script:
		pass
	else:
		keyframe.set_script(KEYFRAME_SCRIPT_CUSTOM.duplicate())
		keyframe.has_custom_script = true
		keyframe.edited.emit()
	await get_tree().process_frame
	EditorInterface.edit_resource(keyframe.get_script())
	EditorInterface.edit_script(keyframe.get_script(), 5, 1)
	EditorInterface.get_editor_main_screen().get_child(2).visible = true


#region UNDO/REDO

func undo_redo_strokes_start():
	_strokes_before = _get_editing_brush().get_strokes_duplicate()


func undo_redo_strokes_complete(name):
	var brush = _get_editing_brush()
	var strokes_after = brush.get_strokes_duplicate()
	
	var undo_redo = get_undo_redo()
	undo_redo.create_action(name)
	undo_redo.add_undo_property(brush, "stroke_data", _strokes_before)
	undo_redo.add_do_property(brush, "stroke_data", strokes_after)
	undo_redo.add_do_method(brush, "draw")
	undo_redo.add_undo_method(brush, "draw")
	
	undo_redo.commit_action(false)

#endregion


#region SHADER

func write_shader(anti_alias: bool, boiling: bool):
	var shader_source = ""
	shader_source += "shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;\n
varying vec4 modulate;
"
	if boiling:
		shader_source += "
global uniform sampler2D goolash_boil_noise : repeat_enable;
global uniform float goolash_frame;
"
	shader_source += "
void vertex() {
	modulate = COLOR;
}
void fragment() {
	COLOR.rgb = modulate.rgb;"
	
	if boiling:
		shader_source += "
	vec2 uv = SCREEN_UV;
	vec2 noise_uv = UV / 6.0;
	float frame = floor(goolash_frame / 4.0);
	noise_uv += vec2(frame * 0.05, frame * PI);
	uv += (texture(goolash_boil_noise, noise_uv).rg - 0.5) * 0.001;"
	elif anti_alias:
		shader_source += "	vec2 uv = SCREEN_UV;"
	
	if anti_alias:
		shader_source += "
	float a = 0.0;
	a += texture(screen_texture, uv).r * 2.0;
	for (float i = 0.0; i < 1.0; i += 1.0 / 3.0) {
		a += texture(screen_texture, uv + vec2(sin(i * TAU + 0.8), cos(i * TAU + 0.8)) * 1.5 * SCREEN_PIXEL_SIZE).r;
		a += texture(screen_texture, uv + vec2(sin(i * TAU), cos(i * TAU)) * 1.0 * SCREEN_PIXEL_SIZE).r;
	}
	a = smoothstep(0.2, 0.6, a / 8.0);\n
	
	COLOR.a = a * modulate.a;\n"
	else:
		shader_source += "
	COLOR.a = texture(screen_texture, SCREEN_UV).r;"
	
	shader_source += "
}"
	var file := FileAccess.open("res://addons/goolash/brush_stroke.gdshader", FileAccess.WRITE)
	file.store_string(shader_source)
	file.close()

#endregion


static func is_editable(node):
	return node.scene_file_path == "" or node.get_tree().edited_scene_root == node


static func douglas_peucker(points: PackedVector2Array, tolerance := 1.0, level := 0) -> PackedVector2Array:
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
		var results1 = douglas_peucker(points.slice(0, index+1), tolerance, level + 1)
		var results2 = douglas_peucker(points.slice(index), tolerance, level + 1)
		
		return results1 + results2.slice(1)
	else:
		return PackedVector2Array([points[0], points[points.size() - 1]])

