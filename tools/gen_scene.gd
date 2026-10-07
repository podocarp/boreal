extends SceneTree
## Code-author scenes/main.tscn (FACTORY rule 1: .tscn is generated output).
## Run: godot --headless --path . --script res://tools/gen_scene.gd

func _init():
	var root := Node3D.new()
	root.name = "Main"
	var scr := load("res://scenes/main.gd")
	root.set_script(scr)
	var ps := PackedScene.new()
	var err := ps.pack(root)
	assert(err == OK, "pack failed")
	err = ResourceSaver.save(ps, "res://scenes/main.tscn")
	assert(err == OK, "save failed")
	root.free()
	print("PASS gen_scene: scenes/main.tscn written")
	quit(0)
