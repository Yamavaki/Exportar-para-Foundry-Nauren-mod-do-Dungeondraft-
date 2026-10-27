extends Reference
# Núcleo da exportação "Foundry (Nauren)".
# Não tem script_class nem start(): é só uma biblioteca carregada pelos scripts de formato
# e pela ferramenta. Não mexe na janela de exportação nem em nós de outros mods.

const MOD_VERSION = "1.0.5"
const LOG_PREFIX = "[NaurenFoundry] "
const STATE_META = "nauren_foundry_export_state"

var G = null                 # Global do Dungeondraft (injetado por quem cria o núcleo)


func say(msg):
	print(LOG_PREFIX + str(msg))


# ---------------------------------------------------------------------------
# Estado compartilhado entre a ferramenta (janela de exportação) e os formatos
# ---------------------------------------------------------------------------

func get_state() -> Dictionary:
	if G == null or G.Editor == null:
		return {}
	if not G.Editor.has_meta(STATE_META):
		# Todas as chaves já existem desde o início: a exportação (outra thread) só troca valores,
		# nunca cria chaves enquanto a ferramenta lê o dicionário.
		G.Editor.set_meta(STATE_META, {
			"all_levels": false,     # caixa "todos os andares" marcada
			"session": null,         # sessão de exportação de vários andares em andamento
			"last_result": null,     # resultado da última exportação
			"notify": null,          # resultado a avisar (lido pela ferramenta no update)
			"source_index": -1,      # andar escolhido na janela (gravado ao clicar em Exportar)
			"frame_ratios": {}       # resource_path -> abertura medida (preenchido na thread principal)
		})
	return G.Editor.get_meta(STATE_META)


# ---------------------------------------------------------------------------
# Andares
# ---------------------------------------------------------------------------

func get_levels() -> Array:
	if G == null or G.World == null:
		return []
	if not ("levels" in G.World):
		return []
	var lv = G.World.levels
	if lv == null:
		return []
	var out = []
	for l in lv:
		out.append(l)
	return out


func level_index_of(level) -> int:
	var lv = get_levels()
	for i in range(lv.size()):
		if lv[i] == level:
			return i
	return -1


# Andar que está sendo exportado: o escolhido em "Source level" da janela de exportação,
# senão o andar ativo.
func get_source_level():
	var lv = get_levels()
	var idx = int(get_state().get("source_index", -1))
	if idx >= 0 and idx < lv.size():
		return lv[idx]
	if G.World.has_method("GetCurrentLevel"):
		return G.World.GetCurrentLevel()
	return null


func level_label(level, index: int) -> String:
	var label = ""
	if level != null and level.get("Label") != null:
		label = str(level.Label)
	if label == "":
		label = "Andar " + str(index + 1)
	return label


func get_export_dialog():
	if G == null or G.Editor == null:
		return null
	if not ("Windows" in G.Editor):
		return null
	var w = G.Editor.Windows
	if w is Dictionary and w.has("Export"):
		return w["Export"]
	return null


# ---------------------------------------------------------------------------
# Nomes de arquivo
# ---------------------------------------------------------------------------

func sanitize(s: String) -> String:
	var out = s.strip_edges()
	for ch in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\t", "\n"]:
		out = out.replace(ch, "")
	out = out.replace(" ", "_")
	while out.find("__") != -1:
		out = out.replace("__", "_")
	if out == "":
		out = "Andar"
	return out


# Número do andar contado de baixo para cima (1 = térreo). No Dungeondraft a lista de andares
# vem de cima para baixo: o índice 0 é o andar mais alto.
func floor_number(index: int, count: int) -> int:
	return count - index if count > 0 else index + 1


func level_suffix(index: int, label: String, count: int = 0) -> String:
	return "_" + str(floor_number(index, count)) + "_" + sanitize(label)


# Caminho base (sem extensão) para um andar. Com um andar só, não acrescenta nada.
func base_for_level(base_path: String, index: int, label: String, level_count: int) -> String:
	if level_count <= 1:
		return base_path
	var suffix = level_suffix(index, label, level_count)
	if base_path.ends_with(suffix):
		return base_path
	return base_path + suffix


# Tira um sufixo "_<n>_<nome do andar>" que já esteja no nome escolhido (ex.: reexportando).
func strip_level_suffix(base_path: String) -> String:
	var lv = get_levels()
	if lv.size() <= 1:
		return base_path
	for i in range(lv.size()):
		for suffix in [level_suffix(i, level_label(lv[i], i), lv.size()), level_suffix(i, level_label(lv[i], i))]:
			if base_path.ends_with(suffix):
				return base_path.substr(0, base_path.length() - suffix.length())
	return base_path


# ---------------------------------------------------------------------------
# Conversão para JSON (Vector2 vira {x, y}, como no .dd2vtt)
# ---------------------------------------------------------------------------

func to_json_value(v):
	if v is Vector2:
		return {"x": v.x, "y": v.y}
	if v is Color:
		return v.to_html(true)
	if v is Dictionary:
		var d = {}
		for k in v.keys():
			d[str(k)] = to_json_value(v[k])
		return d
	if v is Array or typeof(v) in [TYPE_VECTOR2_ARRAY, TYPE_INT_ARRAY, TYPE_REAL_ARRAY, TYPE_STRING_ARRAY]:
		var a = []
		for item in v:
			a.append(to_json_value(item))
		return a
	return v


# ---------------------------------------------------------------------------
# Dados do .dd2vtt (sem imagem)
# ---------------------------------------------------------------------------

# Filhos de Objects que não são objetos do Dungeondraft (ex.: a imagem de traço que o
# Unofficial Patch coloca ali). A leitura das paredes dos objetos trava com eles.
func has_foreign_objects(level) -> bool:
	if level == null or level.get("Objects") == null:
		return false
	for child in level.Objects.get_children():
		if not child.has_meta("node_id"):
			return true
	return false


func build_vtt_data(ppi: int, level) -> Dictionary:
	var ex = G.Exporter
	var data = {}
	var foreign = has_foreign_objects(level)
	if not foreign and ex.has_method("ExportForVTT"):
		# Métodos C# chamados do GDScript precisam de todos os argumentos (inclusive os opcionais).
		var raw = ex.ExportForVTT(ppi, null)
		if raw is Dictionary:
			data = to_json_value(raw)
	if data.empty():
		# Montagem peça por peça (usada quando há objetos estranhos na camada de objetos).
		data["format"] = 0.3
		data["resolution"] = to_json_value(ex.ExportResolution(ppi))
		data["line_of_sight"] = to_json_value(ex.ExportLOS())
		if foreign:
			data["objects_line_of_sight"] = []
			say("Camada de objetos com itens de outro mod (ex.: imagem de traço): paredes de objetos não exportadas.")
		else:
			data["objects_line_of_sight"] = to_json_value(ex.ExportObjectsLOS())
		data["portals"] = to_json_value(ex.ExportPortals())
		data["environment"] = {"baked_lighting": true, "ambient_light": "ffffffff"}
		data["lights"] = to_json_value(ex.ExportLights())
	if data.has("image"):
		data.erase("image")
	return data


# ---------------------------------------------------------------------------
# Portais: moldura usada e abertura medida pela arte
# ---------------------------------------------------------------------------

func collect_portal_nodes(level) -> Array:
	var out = []
	if level == null:
		return out
	if level.get("Portals") != null:
		for p in level.Portals.get_children():
			if p.get("WallID") != null:
				out.append(p)
	if level.get("Walls") != null:
		var stack = level.Walls.get_children()
		while stack.size() > 0:
			var n = stack.pop_back()
			if n.get("WallID") != null:
				if not out.has(n):
					out.append(n)
			else:
				for c in n.get_children():
					stack.append(c)
	return out


func texture_name(portal) -> String:
	var tex = portal.get("Texture")
	if tex == null:
		return ""
	var path = str(tex.resource_path)
	if path == "":
		return ""
	return path.get_file().get_basename()


# Razão abertura / largura visível da moldura (0..1), lendo a transparência da arte.
# Molduras são postes com vão no meio; usa o MAIOR vão entre trechos preenchidos.
# Devolve -1 quando não dá para medir (ex.: arte de porta inteira, sem vão).
# ATENÇÃO: lê a textura da placa de vídeo -> só chamar na thread principal (ver precompute_frames).
func measure_frame_ratio(tex) -> float:
	if tex == null or not tex.has_method("get_data"):
		return -1.0
	var img = tex.get_data()
	if img == null or not (img is Image):
		return -1.0
	if img.is_compressed():
		img.decompress()
	img.lock()
	var w = img.get_width()
	var h = img.get_height()
	var step_y = max(1, int(h / 64))
	var cols = []
	for x in range(w):
		var filled = false
		var y = 0
		while y < h:
			if img.get_pixel(x, y).a > 0.08:
				filled = true
				break
			y += step_y
		cols.append(filled)
	img.unlock()
	var runs = []
	var start = -1
	for x in range(w):
		if cols[x] and start == -1:
			start = x
		elif not cols[x] and start != -1:
			runs.append([start, x - 1])
			start = -1
	if start != -1:
		runs.append([start, w - 1])
	if runs.size() < 2:
		return -1.0
	# O Dungeondraft exporta o portal de ponta a ponta da parte visível da moldura.
	var outer = float(runs[runs.size() - 1][1] - runs[0][0] + 1)
	var widest = 0.0
	for i in range(runs.size() - 1):
		widest = max(widest, float(runs[i + 1][0] - runs[i][1] - 1))
	if outer <= 0:
		return -1.0
	var r = widest / outer
	return r if r > 0.4 and r < 0.99 else -1.0


# Mede as molduras do andar e guarda no estado. Chamado na thread principal
# (ao abrir a janela de exportação e ao clicar em Exportar).
func precompute_frames(level) -> void:
	var cache = get_state().get("frame_ratios")
	if cache == null:
		return
	for node in collect_portal_nodes(level):
		if node.get("Closed") == false:
			continue
		var tex = node.get("Texture")
		if tex == null:
			continue
		var key = str(tex.resource_path)
		if key == "" or cache.has(key):
			continue
		cache[key] = measure_frame_ratio(tex)


# Durante a exportação: só lê o que já foi medido.
func frame_opening_ratio(portal) -> float:
	var tex = portal.get("Texture")
	if tex == null:
		return -1.0
	var key = str(tex.resource_path)
	var cache = get_state().get("frame_ratios")
	if key != "" and cache != null and cache.has(key):
		return float(cache[key])
	return -1.0


func _cells(v: Vector2) -> Vector2:
	var gs = float(G.World.get("GridSize")) if G.World.get("GridSize") != null else 256.0
	if gs <= 0:
		gs = 256.0
	return v / gs


func _entry_mid(entry) -> Vector2:
	if entry.has("bounds") and entry["bounds"] is Array and entry["bounds"].size() >= 2:
		var a = entry["bounds"][0]
		var b = entry["bounds"][1]
		return Vector2((a["x"] + b["x"]) / 2.0, (a["y"] + b["y"]) / 2.0)
	if entry.has("position"):
		return Vector2(entry["position"]["x"], entry["position"]["y"])
	return Vector2.ZERO


func _entry_len(entry) -> float:
	if entry.has("bounds") and entry["bounds"] is Array and entry["bounds"].size() >= 2:
		var a = entry["bounds"][0]
		var b = entry["bounds"][1]
		return Vector2(a["x"], a["y"]).distance_to(Vector2(b["x"], b["y"]))
	return 0.0


# Junta a cada portal do .dd2vtt as informações extras do nó correspondente
# (casado pelo ponto do meio, em quadrados).
func add_portal_extras(data: Dictionary, level) -> int:
	if not data.has("portals") or not (data["portals"] is Array):
		return 0
	var nodes = collect_portal_nodes(level)
	if nodes.empty():
		return 0
	var mids = []
	for n in nodes:
		var b = n.get("Begin")
		var e = n.get("End")
		if b == null or e == null or b == e:
			# Portal solto: usa a posição do próprio nó.
			var gp = n.get("global_position")
			mids.append(_cells(gp) if gp != null else null)
		else:
			mids.append(_cells((b + e) / 2.0))
	# Deslocamento entre as coordenadas do mundo e as do arquivo (origem do mapa).
	var origin = Vector2.ZERO
	if data.has("resolution") and data["resolution"].has("map_origin"):
		var mo = data["resolution"]["map_origin"]
		origin = Vector2(mo["x"], mo["y"])
	var offsets = [Vector2.ZERO, origin, -origin]
	var best_offset = Vector2.ZERO
	var best_err = INF
	for off in offsets:
		var err = 0.0
		for entry in data["portals"]:
			var m = _entry_mid(entry) - off
			var d = INF
			for mid in mids:
				if mid != null:
					d = min(d, m.distance_to(mid))
			err += d
		if err < best_err:
			best_err = err
			best_offset = off
	var matched = 0
	var used = {}
	for entry in data["portals"]:
		var m = _entry_mid(entry) - best_offset
		var best_i = -1
		var best_d = 0.35  # no máximo ~1/3 de quadrado de distância
		for i in range(nodes.size()):
			if used.has(i) or mids[i] == null:
				continue
			var d = m.distance_to(mids[i])
			if d < best_d:
				best_d = d
				best_i = i
		if best_i == -1:
			continue
		used[best_i] = true
		var node = nodes[best_i]
		var closed = node.get("Closed")
		var kind = "window" if closed == false else "door"
		var extra = {
			"texture": texture_name(node),
			"kind": kind,
			"flip": bool(node.get("Flip")) if node.get("Flip") != null else false,
			"freestanding": bool(node.get("IsFreestanding")) if node.get("IsFreestanding") != null else false
		}
		if kind == "door":
			var ratio = frame_opening_ratio(node)
			var length = _entry_len(entry)
			if ratio > 0 and length > 0:
				extra["opening"] = stepify(length * ratio, 0.001)
				extra["opening_ratio"] = stepify(ratio, 0.0001)
		entry["nauren"] = extra
		matched += 1
	return matched


# ---------------------------------------------------------------------------
# Paredes com "Allow Light" (Unofficial Patch)
# ---------------------------------------------------------------------------
# O Unofficial Patch deixa a luz passar zerando o light_mask das sombras (LightOccluder2D)
# da parede e guarda as paredes marcadas num arquivo. O .dd2vtt do Dungeondraft não sabe
# disso, então o mod grava a lista em nauren.light_walls para o importador.

const UP_ALLOW_LIGHT_FILE = "user://UnofficialPatch/fixwallbug_blocklight.json"


func _collect_occluders(node, out: Array) -> void:
	for c in node.get_children():
		if c.get_class() == "LightOccluder2D":
			out.append(c)
		if c.get_child_count() > 0:
			_collect_occluders(c, out)


func _wall_fingerprint(wall) -> String:
	var pts = wall.get("Points")
	if pts == null or pts.size() == 0:
		return ""
	var parts = []
	for p in pts:
		parts.append(str(int(p.x)) + "," + str(int(p.y)))
	var tex = wall.get("Texture")
	var tex_path = str(tex.resource_path) if tex != null else ""
	return tex_path + "|" + PoolStringArray(parts).join(";")


func _saved_allow_light() -> Dictionary:
	var f = File.new()
	if not f.file_exists(UP_ALLOW_LIGHT_FILE):
		return {}
	if f.open(UP_ALLOW_LIGHT_FILE, File.READ) != OK:
		return {}
	var parsed = JSON.parse(f.get_as_text())
	f.close()
	if parsed.error == OK and parsed.result is Dictionary:
		return parsed.result
	return {}


# 2 = parede marcada com Allow Light no arquivo do Unofficial Patch; 0 = não.
# (A máscara de luz das sombras NÃO serve: durante a exportação o Dungeondraft muda a máscara
#  dos andares que não estão sendo exportados, e todas as paredes pareciam deixar a luz passar.)
func _allow_light_kind(wall, saved: Dictionary) -> int:
	var fp = _wall_fingerprint(wall)
	return 2 if fp != "" and saved.has(fp) else 0


# Lista das paredes com "Allow Light" do andar, em quadrados, nas coordenadas do arquivo.
func light_walls(data: Dictionary, level) -> Array:
	if level == null or level.get("Walls") == null:
		return []
	var saved = _saved_allow_light()
	var polys = []
	for wall in level.Walls.get_children():
		if not is_instance_valid(wall) or wall.get("Points") == null:
			continue
		var kind = _allow_light_kind(wall, saved)
		if kind == 0:
			continue
		var pts = []
		for p in wall.Points:
			pts.append(_cells(p))
		if pts.size() >= 2:
			polys.append({"points": pts, "loop": bool(wall.get("Loop")) if wall.get("Loop") != null else false, "kind": kind})
	if polys.empty():
		return []
	# Mesmo deslocamento das paredes do arquivo (origem do mapa): escolhe o que encaixa nos vértices.
	var verts = []
	for line in data.get("line_of_sight", []):
		for v in line:
			verts.append(Vector2(v["x"], v["y"]))
	var origin = Vector2.ZERO
	if data.has("resolution") and data["resolution"].has("map_origin"):
		var mo = data["resolution"]["map_origin"]
		origin = Vector2(mo["x"], mo["y"])
	var best_off = Vector2.ZERO
	var best_err = INF
	if not verts.empty():
		for off in [Vector2.ZERO, origin, -origin]:
			var err = 0.0
			for poly in polys:
				for c in poly["points"]:
					var d = INF
					for v in verts:
						d = min(d, (c + off).distance_to(v))
					err += min(d, 5.0)
			if err < best_err:
				best_err = err
				best_off = off
	var out = []
	for poly in polys:
		var cells = []
		for c in poly["points"]:
			var q = c + best_off
			cells.append({"x": stepify(q.x, 0.0001), "y": stepify(q.y, 0.0001)})
		out.append({"points": cells, "loop": poly["loop"]})
	return out


# ---------------------------------------------------------------------------
# Gravação
# ---------------------------------------------------------------------------

func write_bytes(path: String, bytes: PoolByteArray) -> bool:
	var f = File.new()
	var err = f.open(path, File.WRITE)
	if err != OK:
		say("Não consegui gravar " + path + " (erro " + str(err) + ")")
		return false
	f.store_buffer(bytes)
	f.close()
	return true


func write_json(path: String, data: Dictionary) -> bool:
	var f = File.new()
	var err = f.open(path, File.WRITE)
	if err != OK:
		say("Não consegui gravar " + path + " (erro " + str(err) + ")")
		return false
	f.store_string(JSON.print(data, "\t"))
	f.close()
	return true


func read_image_bytes(image) -> PoolByteArray:
	if image == null:
		return PoolByteArray()
	if image is File:
		image.seek(0)
		return image.get_buffer(image.get_len())
	if image is Image:
		return image.save_png_to_buffer() if image.has_method("save_png_to_buffer") else PoolByteArray()
	return PoolByteArray()


# ---------------------------------------------------------------------------
# Exportação de um andar (chamada pelo process() dos formatos)
# ---------------------------------------------------------------------------

func export_level(path: String, image, ppi: int, image_ext: String) -> Dictionary:
	var result = {"ok": false, "files": [], "message": ""}
	var state = get_state()
	var level = get_source_level()
	var levels = get_levels()
	var index = level_index_of(level)
	if index < 0:
		index = 0
	var label = level_label(level, index)
	if image is File:
		say("Imagem entregue pelo Dungeondraft: " + str(image.get_path()))

	# Base do nome: numa sessão de vários andares, a do primeiro andar; senão, o que foi escolhido.
	var chosen_base = path.get_basename()
	var session = state.get("session")
	var base = chosen_base
	if session != null and session.has("base"):
		base = session["base"]
	else:
		base = strip_level_suffix(chosen_base)
	var final_base = base_for_level(base, index, label, levels.size())
	var json_path = final_base + ".dd2vtt"
	var image_path = final_base + "." + image_ext

	# Imagem separada.
	var bytes = read_image_bytes(image)
	if bytes.size() == 0:
		result["message"] = "O Dungeondraft não entregou a imagem do mapa."
		say(result["message"])
		return result
	if not write_bytes(image_path, bytes):
		result["message"] = "Não consegui gravar a imagem em " + image_path
		return result

	# .dd2vtt sem imagem, com os extras.
	var data = build_vtt_data(ppi, level)
	var matched = add_portal_extras(data, level)
	var light_list = light_walls(data, level)
	data["nauren"] = {
		"version": 1,
		"mod_version": MOD_VERSION,
		"image_file": image_path.get_file(),
		"image_format": image_ext,
		"ppi": ppi,
		"level": {"index": index, "floor": levels.size() - 1 - index, "label": label, "count": levels.size(), "order": "dd_top_first"},
		"light_walls": light_list
	}
	if not write_json(json_path, data):
		result["message"] = "Não consegui gravar " + json_path
		return result

	# Se o Dungeondraft escolheu um caminho diferente (outro nome), não deixa arquivo vazio para trás.
	if path != json_path:
		var dir = Directory.new()
		if dir.file_exists(path):
			var f = File.new()
			if f.open(path, File.READ) == OK:
				var size_b = f.get_len()
				f.close()
				if size_b == 0:
					dir.remove(path)

	result["ok"] = true
	result["files"] = [json_path.get_file(), image_path.get_file()]
	result["index"] = index
	result["label"] = label
	result["base"] = base
	result["ppi"] = ppi
	result["warn"] = ""
	var mb = bytes.size() / 1048576.0
	if image_ext == "png" and mb > 5.0:
		result["warn"] = "A imagem PNG ficou com %.1f MB. O Imgur transforma PNG acima de 5 MB em JPG, e o fundo transparente vira branco. Use o formato WebP ou um PPI menor (100 a 150 já basta no Foundry)." % mb
	result["portals"] = data.get("portals", []).size()
	result["matched"] = matched
	result["light_walls"] = light_list.size()
	result["message"] = "Andar " + str(index + 1) + " (" + label + "): " + json_path.get_file() + " + " + image_path.get_file()
	say(result["message"] + " | portais com moldura identificada: " + str(matched) + "/" + str(result["portals"]) + " | paredes com Allow Light: " + str(light_list.size()))
	state["last_result"] = result
	return result
