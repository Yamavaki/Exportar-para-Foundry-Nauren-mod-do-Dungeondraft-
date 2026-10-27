# Integra o "Foundry Nauren" na janela de exportação do Dungeondraft:
#  - caixa de opções que só aparece quando um formato "Foundry Nauren" está escolhido;
#  - "Exportar todos os andares de uma vez": um clique em Exportar e o mod exporta os outros
#    andares sozinho, com as mesmas opções da janela;
#  - aviso ao terminar, com os arquivos gravados.
# Não move nem altera controles existentes: só acrescenta os seus, com nomes próprios.

var script_class = "tool"

const FORMAT_PREFIX = "Foundry Nauren"
const BOX_NAME = "NaurenFoundryBox"
const CHECK_NAME = "NaurenFoundryAllLevels"
const NEXT_DELAY_MS = 1500      # espera depois de um andar antes de começar o próximo
const WATCHDOG_MS = 300000      # 5 min sem terminar um andar = desiste
const POLL_META = "nauren_foundry_poll_timer"

var _core = null
var _dialog = null           # janela de exportação do Dungeondraft
var _box = null
var _check = null
var _hint = null
var _hooked = false
var _retry = 0.0
var _info = null             # AcceptDialog de aviso
var _cancel_btn = null


func start():
	var script = ResourceLoader.load(Global.Root + "library/core.gd", "GDScript", true)
	if script != null:
		_core = script.new()
		_core.G = Global
	_try_hook()
	_start_poll_timer()


func update(delta):
	if not _hooked:
		_retry += delta
		if _retry > 1.0:
			_retry = 0.0
			_try_hook()


# O update() dos mods não roda enquanto uma janela do Dungeondraft (como a de exportação)
# está aberta. Por isso a sequência de andares é tocada por um Timer próprio, que roda sempre.
func _start_poll_timer():
	if Engine.has_meta(POLL_META):
		var old = Engine.get_meta(POLL_META)
		if old != null and is_instance_valid(old):
			old.queue_free()
	var t = Timer.new()
	t.name = "NaurenFoundryPoll"
	t.wait_time = 0.2
	t.autostart = true
	t.pause_mode = Node.PAUSE_MODE_PROCESS
	t.connect("timeout", self, "_poll")
	Engine.set_meta(POLL_META, t)
	Global.Editor.add_child(t)


func _poll():
	if _core == null:
		return
	if not _hooked:
		_try_hook()
	var state = _core.get_state()
	var session = state.get("session")
	if session != null and Global.World != null and session.get("world", 0) != Global.World.get_instance_id():
		# Outro mapa foi aberto: a sequência anterior não vale mais.
		state["session"] = null
		session = null
	if state.has("notify") and state["notify"] != null:
		var result = state["notify"]
		state["notify"] = null
		_on_export_done(result)
		return
	if session != null:
		var now = OS.get_ticks_msec()
		if session.has("next_at") and now >= session["next_at"]:
			session.erase("next_at")
			_auto_export_next()
		elif session.has("waiting_since") and now - session["waiting_since"] > WATCHDOG_MS:
			session.erase("waiting_since")
			_core.say("O andar automático não terminou a tempo; sequência interrompida.")
			_stop_session("O Dungeondraft não terminou de exportar o próximo andar sozinho. Exporte os andares que faltam normalmente (um por vez).")


# ---------------------------------------------------------------------------
# Janela de exportação
# ---------------------------------------------------------------------------

func _try_hook():
	if _hooked or _core == null:
		return
	var dialog = _core.get_export_dialog()
	if dialog == null or not is_instance_valid(dialog):
		return
	_dialog = dialog
	_build_box()
	if not _dialog.is_connected("about_to_show", self, "_on_dialog_about_to_show"):
		_dialog.connect("about_to_show", self, "_on_dialog_about_to_show")
	var mode = _mode_options()
	if mode != null and not mode.is_connected("item_selected", self, "_on_mode_selected"):
		mode.connect("item_selected", self, "_on_mode_selected")
	var src = _source_options()
	if src != null and not src.is_connected("item_selected", self, "_on_source_selected"):
		src.connect("item_selected", self, "_on_source_selected")
	var okay = _dialog.find_node("OkayButton", true, false)
	if okay != null and not okay.is_connected("pressed", self, "_on_okay_pressed"):
		okay.connect("pressed", self, "_on_okay_pressed")
	_hooked = true
	_refresh_box()


func _mode_options():
	if _dialog == null:
		return null
	return _dialog.find_node("ExportModeOptions", true, false)


func _source_options():
	if _dialog == null:
		return null
	return _dialog.find_node("SourceLevelOptions", true, false)


func _is_our_format_selected() -> bool:
	var mode = _mode_options()
	if mode == null or mode.selected < 0:
		return false
	return str(mode.get_item_text(mode.selected)).begins_with(FORMAT_PREFIX)


func _build_box():
	var valign = _dialog.find_node("VAlign", true, false)
	if valign == null:
		_core.say("Não achei a área de opções da janela de exportação; a caixa Foundry (Nauren) não será mostrada.")
		return
	var old = _dialog.find_node(BOX_NAME, true, false)
	if old != null:
		old.get_parent().remove_child(old)
		old.queue_free()

	_box = VBoxContainer.new()
	_box.name = BOX_NAME
	_box.add_constant_override("separation", 4)

	var sep = HSeparator.new()
	_box.add_child(sep)

	var title = Label.new()
	title.text = "Foundry (Nauren)"
	_box.add_child(title)

	_check = CheckButton.new()
	_check.name = CHECK_NAME
	_check.text = "Exportar todos os andares de uma vez"
	_check.hint_tooltip = "Clique em Exportar uma vez: o mod exporta o andar escolhido e depois os outros sozinho,\ncom as mesmas opções. Os arquivos saem com o número e o nome do andar."
	_check.connect("toggled", self, "_on_check_toggled")
	_box.add_child(_check)

	_hint = Label.new()
	_hint.autowrap = true
	# Largura mínima fixa: Label com quebra de linha e largura 0 mede uma altura enorme no Godot 3.
	_hint.rect_min_size = Vector2(260, 0)
	_hint.modulate = Color(1, 1, 1, 0.75)
	_hint.text = "Grava o .dd2vtt sem imagem e a imagem separada, lado a lado."
	_box.add_child(_hint)

	_cancel_btn = Button.new()
	_cancel_btn.name = "NaurenFoundryCancelSequence"
	_cancel_btn.text = "Cancelar a sequência de andares"
	_cancel_btn.visible = false
	_cancel_btn.connect("pressed", self, "_stop_session", [""])
	_box.add_child(_cancel_btn)

	# Fica logo antes da linha dos botões (Exportar/Cancelar), sem mexer nos outros controles.
	var okay = _dialog.find_node("OkayButton", true, false)
	valign.add_child(_box)
	if okay != null:
		var anchor = okay
		while anchor != null and anchor.get_parent() != valign:
			anchor = anchor.get_parent()
		if anchor != null:
			valign.move_child(_box, anchor.get_index())


func _refresh_box():
	if _box == null or not is_instance_valid(_box):
		return
	var ours = _is_our_format_selected()
	_box.visible = ours
	var count = _core.get_levels().size()
	var state = _core.get_state()
	_check.disabled = count <= 1
	_check.set_block_signals(true)
	_check.pressed = count > 1 and bool(state.get("all_levels", false))
	_check.set_block_signals(false)
	var session = state.get("session")
	if _cancel_btn != null:
		_cancel_btn.visible = session != null
	call_deferred("_fit_dialog")
	if session != null:
		_hint.text = "Exportando todos os andares sozinho: %d de %d prontos. Aguarde…" % [session["done"].size(), count]
	elif count <= 1:
		_hint.text = "Grava o .dd2vtt sem imagem e a imagem separada, lado a lado. (Este mapa tem um andar só.)"
	else:
		_hint.text = "Grava o .dd2vtt sem imagem e a imagem separada, lado a lado, com o número e o nome do andar no nome do arquivo."


func _on_mode_selected(_index):
	_refresh_box()


func _on_source_selected(index):
	# Guarda o andar escolhido já aqui (antes do clique em Exportar) e mede as molduras na thread principal.
	_core.get_state()["source_index"] = index
	var lv = _core.get_levels()
	if index >= 0 and index < lv.size():
		_core.precompute_frames(lv[index])


func _on_okay_pressed():
	# Guarda o andar escolhido e mede as molduras antes de a exportação começar (thread principal).
	var src = _source_options()
	var state = _core.get_state()
	var idx = src.selected if src != null else -1
	if idx < 0 and Global.World.has_method("GetCurrentLevel"):
		idx = _core.level_index_of(Global.World.GetCurrentLevel())
	state["source_index"] = idx
	var lv = _core.get_levels()
	if idx >= 0 and idx < lv.size():
		_core.precompute_frames(lv[idx])


# Só aumenta a janela de exportação quando o conteúdo não cabe (nunca encolhe), na altura
# E na largura: clique fora do retângulo da janela é engolido pelo Godot, então nada pode
# ficar desenhado para fora dela.
func _fit_dialog():
	if _dialog == null or not is_instance_valid(_dialog) or not _dialog.visible:
		return
	var valign = _dialog.find_node("VAlign", true, false)
	if valign == null:
		return
	var pad = Vector2.ZERO
	var p = valign.get_parent()
	while p != null and p != _dialog:
		if p is MarginContainer:
			pad.x += p.get_constant("margin_left") + p.get_constant("margin_right")
			pad.y += p.get_constant("margin_top") + p.get_constant("margin_bottom")
		p = p.get_parent()
	var content = valign.get_combined_minimum_size()
	var need_w = content.x + pad.x + 16
	var need_h = content.y + pad.y + 40
	var size = _dialog.rect_size
	var grown = Vector2(max(size.x, need_w), max(size.y, need_h))
	if grown == size:
		return
	_dialog.rect_size = grown
	# Mantém a janela inteira na tela.
	var screen = OS.window_size
	var pos = _dialog.rect_position
	if pos.x + grown.x > screen.x:
		pos.x = max(0, screen.x - grown.x - 10)
	if pos.y + grown.y > screen.y:
		pos.y = max(0, screen.y - grown.y - 10)
	_dialog.rect_position = pos


func _on_check_toggled(pressed):
	_core.get_state()["all_levels"] = pressed


func _on_dialog_about_to_show():
	_refresh_box()
	var src = _source_options()
	if src != null and src.selected >= 0 and _core.get_state().get("session") == null:
		_core.get_state()["source_index"] = src.selected
	if Global.World.has_method("GetCurrentLevel"):
		_core.precompute_frames(Global.World.GetCurrentLevel())
	var session = _core.get_state().get("session")
	if session != null and session["queue"].size() > 0:
		# Depois que o Dungeondraft preparar a janela, escolhe o andar da vez e o nosso formato.
		call_deferred("_preselect", session["queue"][0], session.get("format_text", ""))


func _preselect(level_index, format_text):
	var src = _source_options()
	if src != null and level_index < src.get_item_count() and src.selected != level_index:
		src.select(level_index)
		src.emit_signal("item_selected", level_index)
	var mode = _mode_options()
	if mode != null and format_text != "":
		for i in range(mode.get_item_count()):
			if mode.get_item_text(i) == format_text and mode.selected != i:
				mode.select(i)
				mode.emit_signal("item_selected", i)
				break
	_refresh_box()


# ---------------------------------------------------------------------------
# Depois de exportar
# ---------------------------------------------------------------------------

func _on_export_done(result):
	var state = _core.get_state()
	var src_opt = _source_options()
	state["source_index"] = src_opt.selected if src_opt != null else -1
	if bool(state.get("ignore_next_result", false)):
		# Andar que já estava exportando quando a sequência foi cancelada: não recomeça nada.
		state["ignore_next_result"] = false
		return
	if not result.get("ok", false):
		state["session"] = null
		_show_info_later("Exportar para Foundry", "Não deu certo: " + str(result.get("message", "erro desconhecido")) + "\n\nDetalhes no log do Dungeondraft (linhas com [NaurenFoundry]).")
		return

	var levels = _core.get_levels()
	var session = state.get("session")
	if session == null and bool(state.get("all_levels", false)) and levels.size() > 1:
		var queue = []
		for i in range(levels.size()):
			if i != result["index"]:
				queue.append(i)
		var mode = _mode_options()
		session = {
			"base": result["base"],
			"done": [result["index"]],
			"files": result["files"].duplicate(),
			"queue": queue,
			"format_text": mode.get_item_text(mode.selected) if mode != null and mode.selected >= 0 else "",
			"world": Global.World.get_instance_id(),
			"ppi": int(result.get("ppi", 0)),
			"warn": str(result.get("warn", ""))
		}
		state["session"] = session
	elif session != null:
		if not session["done"].has(result["index"]):
			session["done"].append(result["index"])
		session["queue"].erase(result["index"])
		for f in result["files"]:
			session["files"].append(f)
		if str(result.get("warn", "")) != "":
			session["warn"] = str(result["warn"])

	if session == null:
		_show_info_later("Exportado para o Foundry", "Arquivos gravados:\n• " + PoolStringArray(result["files"]).join("\n• ") + "\n\nPortas com moldura identificada: %d de %d.\nParedes com Allow Light: %d." % [result.get("matched", 0), result.get("portals", 0), result.get("light_walls", 0)] + _warn_text(result.get("warn", "")))
		return

	session.erase("waiting_since")
	if session["queue"].size() > 0:
		# Próximo andar sozinho, sem perguntar: espera o Dungeondraft terminar de fechar a exportação anterior.
		session["next_at"] = OS.get_ticks_msec() + NEXT_DELAY_MS
		_refresh_box()
	else:
		var files = session["files"]
		state["session"] = null
		_show_info_later("Todos os andares exportados", "Arquivos gravados (%d andares):\n• " % session["done"].size() + PoolStringArray(files).join("\n• ") + _warn_text(session.get("warn", "")))


# Exporta o próximo andar da fila sem abrir janelas: escolhe o andar de origem na janela de
# exportação (como se o usuário escolhesse, para os outros mods acompanharem) e chama o
# exportador do Dungeondraft direto, com o mesmo formato e PPI do primeiro andar.
func _auto_export_next():
	var state = _core.get_state()
	var session = state.get("session")
	if session == null or session["queue"].size() == 0:
		return
	var idx = session["queue"][0]
	if _dialog != null and is_instance_valid(_dialog) and not _dialog.visible:
		# Reabre a janela (os outros mods preparam a exportação ao abrir) e continua em seguida.
		_dialog.popup_centered()
		session["next_at"] = OS.get_ticks_msec() + 400
		return
	_preselect(idx, session.get("format_text", ""))
	var timer = Global.Editor.get_tree().create_timer(0.3, true)
	timer.connect("timeout", self, "_start_export", [idx])


func _start_export(idx):
	var state = _core.get_state()
	var session = state.get("session")
	if session == null:
		return
	var ex = Global.get("Exporter")
	var ppi = int(session.get("ppi", 0))
	if ex == null or not ex.has_method("Start") or ppi <= 0:
		_stop_session("Não deu para exportar os outros andares sozinho nesta versão do Dungeondraft. Exporte cada andar normalmente.")
		return
	state["source_index"] = idx
	var lv = _core.get_levels()
	if idx >= 0 and idx < lv.size():
		_core.precompute_frames(lv[idx])
	var q = _quality_value()
	if q > 0 and ex.get("Quality") != null:
		ex.Quality = q
	session["waiting_since"] = OS.get_ticks_msec()
	_core.say("Exportando sozinho o andar " + str(idx + 1) + " (PPI " + str(ppi) + ").")
	# Modo 4 = formato de mod (o escolhido na janela, que é o nosso). Métodos C#: todos os argumentos.
	ex.Start(4, ppi, str(session["base"]) + ".dd2vtt")


func _quality_value() -> int:
	if _dialog == null:
		return -1
	for n in ["QualitySlider", "QualitySpinBox"]:
		var c = _dialog.find_node(n, true, false)
		if c != null and c.get("value") != null:
			return int(c.value)
	return -1


func _stop_session(reason = ""):
	var state = _core.get_state()
	var session = state.get("session")
	if session != null and session.has("waiting_since"):
		state["ignore_next_result"] = true
	state["session"] = null
	state["source_index"] = -1
	_hide_export_dialog()
	if session != null:
		var head = reason if reason != "" else "Sequência de andares cancelada."
		_show_info("Exportação interrompida", head + "\n\nAndares já exportados: %d.\n• " % session["done"].size() + PoolStringArray(session["files"]).join("\n• "))


# ---------------------------------------------------------------------------
# Diálogos
# ---------------------------------------------------------------------------

# O aviso sai um instante depois: o Dungeondraft ainda está fechando a exportação e pode
# reabrir a janela dele por cima (ela é modal e esconderia o aviso).
func _warn_text(w) -> String:
	return "" if str(w) == "" else "\n\nAtenção: " + str(w)


func _show_info_later(title, text):
	var timer = Global.Editor.get_tree().create_timer(NEXT_DELAY_MS / 1000.0, true)
	timer.connect("timeout", self, "_show_info_now", [title, text])


func _show_info_now(title, text):
	_hide_export_dialog()
	_show_info(title, text)


func _show_info(title, text):
	if _info == null or not is_instance_valid(_info):
		_info = AcceptDialog.new()
		_info.name = "NaurenFoundryInfo"
		Global.Editor.add_child(_info)
	_info.window_title = title
	_info.dialog_text = text
	_info.popup_centered_minsize(Vector2(420, 120))


# Fecha a janela de exportação (senão ela, que é modal, esconde os nossos avisos).
func _hide_export_dialog():
	if _dialog != null and is_instance_valid(_dialog) and _dialog.visible:
		_dialog.hide()
