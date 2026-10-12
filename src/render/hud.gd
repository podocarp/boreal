## Survival HUD: needs bars, core temp, day/clock, inventory, toasts.
## Built in code (rule: scenes are code-authored). Reads GameLoop state each frame; toast
## expiry uses tick counts (sim-driven), never wall-clock.
class_name SurvivalHud
extends Control

const BAR_NAMES := ["hydration", "hunger", "energy", "health"]
const BAR_COLORS := {
	"hydration": Color(0.35, 0.65, 0.95),
	"hunger": Color(0.90, 0.62, 0.25),
	"energy": Color(0.55, 0.85, 0.45),
	"health": Color(0.90, 0.30, 0.28),
}
const TOAST_TICKS := 40  # 10 real s at 0.25 s ticks

var loop: GameLoop
var _bars := {}
var _temp: Label
var _clock: Label
var _inv: Label
var _prompt: Label
var _injury: Label
var _toast: Label
var _weight: Label
var _toast_left := 0
var _seen_toasts := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# dark backing so white text survives pale snow/fog behind it
	var panel := Panel.new()
	panel.name = "NeedsPanel"
	panel.position = Vector2(6, 6)
	panel.size = Vector2(340, 168)
	var pmat := StyleBoxFlat.new()
	pmat.bg_color = Color(0.05, 0.07, 0.10, 0.62)
	pmat.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", pmat)
	add_child(panel)
	var left := VBoxContainer.new()
	left.name = "Needs"
	left.position = Vector2(12, 12)
	add_child(left)
	for n in BAR_NAMES:
		var row := HBoxContainer.new()
		left.add_child(row)
		var lbl := Label.new()
		lbl.text = n.to_upper()
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.custom_minimum_size = Vector2(74, 0)
		row.add_child(lbl)
		var bar := ProgressBar.new()
		bar.name = "Bar_" + n
		bar.custom_minimum_size = Vector2(120, 10)
		bar.show_percentage = false
		bar.max_value = 100.0
		var st := StyleBoxFlat.new()
		st.bg_color = Color(0, 0, 0, 0.55)
		bar.add_theme_stylebox_override("background", st)
		var fg := StyleBoxFlat.new()
		fg.bg_color = BAR_COLORS[n]
		bar.add_theme_stylebox_override("fill", fg)
		row.add_child(bar)
		# Weight-based calorie model: kg + condition word next to the hunger
		# bar (owner directive 2026-10-11 v2 — no 'fat reserve' bar; the
		# internal calorie counter surfaces as WEIGHT).
		if n == "hunger":
			_weight = Label.new()
			_weight.name = "Weight"
			_weight.add_theme_font_size_override("font_size", 12)
			row.add_child(_weight)
		_bars[n] = bar
	_temp = Label.new()
	_temp.name = "CoreTemp"
	_temp.add_theme_font_size_override("font_size", 15)
	left.add_child(_temp)
	_clock = Label.new()
	_clock.name = "Clock"
	_clock.position = Vector2(12, 118)
	_clock.add_theme_font_size_override("font_size", 18)
	add_child(_clock)
	_inv = Label.new()
	_inv.name = "Inventory"
	_inv.position = Vector2(430, 12)
	_inv.add_theme_font_size_override("font_size", 13)
	_inv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_inv.size = Vector2(198, 200)
	_inv.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_inv.add_theme_constant_override("outline_size", 5)
	add_child(_inv)
	_prompt = Label.new()
	_prompt.name = "Prompt"
	_prompt.position = Vector2(180, 300)
	_prompt.size = Vector2(280, 20)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 17)
	_prompt.add_theme_color_override("font_color", Color(1, 1, 0.9))
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_prompt.add_theme_constant_override("outline_size", 6)
	add_child(_prompt)
	_injury = Label.new()
	_injury.name = "Injury"
	_injury.position = Vector2(6, 146)
	_injury.add_theme_font_size_override("font_size", 14)
	_injury.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45))
	_injury.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_injury.add_theme_constant_override("outline_size", 5)
	add_child(_injury)
	_toast = Label.new()
	_toast.name = "Toast"
	_toast.position = Vector2(80, 326)
	_toast.size = Vector2(480, 24)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 17)
	_toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_toast.add_theme_constant_override("outline_size", 6)
	add_child(_toast)


## Context prompt, mirroring TS contextActions tiers 1–2 (spot verbs win over
## the generic gather target, matching interact()'s snare-first dispatch).
func _context_prompt(w: WorldSim, tgt: Variant) -> String:
	for s in w.snares:
		if s.pending != null and s.pending > 0 \
				and sqrt(pow(s.x - w.player.x, 2) + pow(s.z - w.player.z, 2)) < Config.DANGERS.SNARE_COLLECT_DIST_M:
			return "[E] Collect snare game"
	for h in w.fishHoles:
		if h.usesLeft > 0 \
				and sqrt(pow(h.x - w.player.x, 2) + pow(h.z - w.player.z, 2)) < Config.DANGERS.FISH_REACH_M:
			return "[G] Fish the hole" if Items.inv_has(w.inventory, "cordage", 1) \
				else "[G] Fish the hole (needs cordage)"
	if tgt != null:
		return "[E] " + str(Interact.INTERACT_LABEL.get(tgt.kind, tgt.kind))
	return ""


func _process(_d: float) -> void:
	if loop == null or loop.world == null:
		return
	var w := loop.world
	var n := w.needs
	_bars.hydration.value = n.hydration
	_bars.hunger.value = n.hunger
	_bars.energy.value = n.energy
	_bars.health.value = n.health
	# weight + condition word (ok / thin / weakened / malnourished)
	if _weight != null:
		_weight.text = "  %.0f kg (%s)" % [n.weightKg, Needs.weight_word(Needs.weight_band(n))]
	# subtle 'exhausted' status while the drowsiness channel is active
	# (low energy OR sleep deprivation — Change 3)
	var exhausted: bool = float(Needs.compute_debuffs(n).drowsiness) > 0.0
	_temp.text = "CORE %.1f°C  FEELS %.0f°C%s" % [n.coreTemp, w.feels_like(),
		"  EXHAUSTED" if exhausted else ""]
	_clock.text = "DAY %d   %02d:%02d%s" % [w.day, int(w.hourOfDay),
		int(fmod(w.hourOfDay, 1.0) * 60.0), "  (sleeping)" if n.sleeping else ""]
	var lines: Array[String] = []
	for id in w.inventory:
		lines.append("%s ×%d" % [Items.ITEMS[id].label, w.inventory[id]])
	_inv.text = "\n".join(lines)
	var tgt: Variant = Actions.current_target(w) if not n.sleeping else null
	_prompt.text = _context_prompt(w, tgt) if not n.sleeping else ""
	# injury/infection status line (only when wounded)
	if _injury != null:
		if w.injuries.is_empty():
			_injury.text = ""
		else:
			var parts: Array[String] = []
			for inj in w.injuries:
				parts.append("%s %s%s" % [inj.label,
					"INFECTED %.0f%%" % inj.infection if inj.infected \
						else "sev %.0f" % inj.severity,
					"  [H] treat" if (inj.infected or inj.severity > Config.DANGERS.TREAT_SEVERITY_GT) \
						else ""])
			_injury.text = "\n".join(parts)
	# toast: newest sim-log line, held TOAST_TICKS sim ticks
	if loop.toasts.size() < _seen_toasts:
		_seen_toasts = loop.toasts.size()  # restart cleared the loop's toasts
	if loop.toasts.size() > _seen_toasts:
		_toast.text = loop.toasts[loop.toasts.size() - 1]
		_toast_left = TOAST_TICKS
		_seen_toasts = loop.toasts.size()
	elif _toast_left > 0:
		_toast_left -= 1
		if _toast_left <= 0:
			_toast.text = ""
