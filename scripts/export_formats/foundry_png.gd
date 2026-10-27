# Formato de exportação "Foundry Nauren (PNG)".
# Grava o .dd2vtt SEM a imagem e a imagem separada em .png, lado a lado.
# Toda a lógica fica em library/core.gd (compartilhada pelos três formatos).

var script_class = "export_format"
var export_format_name = "Foundry Nauren (PNG)"
var export_file_extension = "dd2vtt"
var export_image_format = "png"
var show_quality_slider = false

var _core = null


func start():
	_get_core()


func _get_core():
	if _core == null:
		var script = ResourceLoader.load(Global.Root + "library/core.gd", "GDScript", true)
		if script != null:
			_core = script.new()
			_core.G = Global
	return _core


func process(path : String, image : File, ppi : int):
	var core = _get_core()
	if core == null:
		print("[NaurenFoundry] Não encontrei library/core.gd dentro da pasta do mod.")
		return
	var result = core.export_level(path, image, ppi, "png")
	var state = core.get_state()
	state["notify"] = result
