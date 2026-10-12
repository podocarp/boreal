## Title / win / death screens, code-authored (FACTORY rule 1): a CanvasLayer
## with a dim full-rect ColorRect + centered labels. While a screen is up it
## accepts ENTER (ui_accept) or a left click and emits start_pressed /
## restart_pressed; visibility itself is driven by the GameState machine
## through show_menu / show_end / hide_all (single source of truth).
class_name GameUi
extends CanvasLayer

signal start_pressed()
signal restart_pressed()

enum Mode { NONE, MENU, END }

var mode: int = Mode.NONE
var headline: Label
var sub: Label
var body: Label
var hint: Label
var _bg: ColorRect
var _box: VBoxContainer

const CONTROLS := """WASD move · SHIFT sprint · mouse look
E interact / collect snare · F feed fire · R melt snow · C cook
Q drink · T eat · X set snare · G fish · B craft · H treat wound
Stay warm, stay fed — search planes pass days 7–10."""


func _ready() -> void:
	build()


## Idempotent build (FACTORY rule 1: code-authored UI). Called from _ready in
## a live run AND explicitly by main.gd so headless scene-construct tests can
## drive the screens without a running process frame.
func build() -> void:
	if _bg != null:
		return
	layer = 10
	_bg = ColorRect.new()
	_bg.name = "Dim"
	_bg.color = Color(0.02, 0.03, 0.05, 0.82)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_bg.gui_input.connect(_on_bg_input)
	add_child(_bg)
	_box = VBoxContainer.new()
	var box := _box
	box.name = "Box"
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE  # clicks fall through to Dim
	add_child(box)
	headline = _label(box, "", 44, HORIZONTAL_ALIGNMENT_CENTER)
	headline.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	headline.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	headline.add_theme_constant_override("outline_size", 10)
	sub = _label(box, "", 17, HORIZONTAL_ALIGNMENT_CENTER)
	sub.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	body = _label(box, "", 16, HORIZONTAL_ALIGNMENT_CENTER)
	body.add_theme_color_override("font_color", Color(0.85, 0.88, 0.92))
	hint = _label(box, "", 22, HORIZONTAL_ALIGNMENT_CENTER)
	hint.add_theme_color_override("font_color", Color(1, 1, 0.9))
	hide_all()


func _label(parent: Control, text: String, size: int, align: int) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func show_menu() -> void:
	mode = Mode.MENU
	headline.text = "BOREAL"
	headline.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	sub.text = "A SOLO SURVIVAL — THE RADIO IS DEAD. THE SEARCH PASSES NEAR DAY 7."
	body.text = CONTROLS
	hint.text = "Press ENTER or click to start"
	_show()


## win=false -> death screen. `detail` carries cause + days survived (death)
## or rescued-on-day-N + days survived (win); main.gd formats it.
func show_end(win: bool, detail: String) -> void:
	mode = Mode.END
	headline.text = "RESCUED" if win else "YOU DIED"
	headline.add_theme_color_override("font_color",
		Color(0.55, 0.85, 0.60) if win else Color(0.90, 0.35, 0.30))
	sub.text = ""
	body.text = detail
	hint.text = "Press ENTER or click to restart"
	_show()


func hide_all() -> void:
	mode = Mode.NONE
	_bg.visible = false
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.visible = false  # labels live here; without this the title text
	                      # stays on screen forever after start (web 0.1.0 bug)


func _show() -> void:
	_bg.visible = true
	_bg.mouse_filter = Control.MOUSE_FILTER_STOP
	_box.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.NONE and event.is_action_pressed("ui_accept"):
		_accept()
		get_viewport().set_input_as_handled()


func _on_bg_input(event: InputEvent) -> void:
	if mode != Mode.NONE and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_accept()


func _accept() -> void:
	if mode == Mode.MENU:
		start_pressed.emit()
	elif mode == Mode.END:
		restart_pressed.emit()
