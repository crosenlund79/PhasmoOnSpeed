class_name AudioCatalog
extends RefCounted
## Every sound cue the game plays, by its stable internal id (the file stem in
## res://assets/audio/), and where a creator replacement goes. The full,
## human-readable catalog is docs/AUDIO_CATALOG.md — keep the two in step
## (tests/test_runner.gd checks this).
##
## A creator file at res://assets/creator/audio/<path>.<fmt> replaces the
## generated placeholder. The other format is accepted as a second choice, and
## numbered variants (<path>_01 … _08) are picked at random per play. Only the
## asset changes: when, where, how loud and how often a sound plays is decided
## by the game exactly as before.

const CREATOR_DIR := "res://assets/creator/audio/"
const MAX_VARIANTS := 8

## id -> [creator path without extension, preferred format]
const CUES := {
	# player
	"footstep": ["player/footstep", "wav"],
	"player_hurt": ["player/hurt", "wav"],
	"player_death": ["player/death", "wav"],
	"pickup": ["player/pickup", "wav"],
	"place_item": ["player/place_item", "wav"],
	# equipment
	"flashlight_click": ["equipment/lantern_shutter", "wav"],
	"needle_tap": ["equipment/witch_needle_tap", "wav"],
	"spirit_box_static": ["equipment/whisper_box_hiss", "ogg"],
	"spirit_box_voice": ["equipment/whisper_box_voice", "wav"],
	"mirror_reveal": ["equipment/mirror_shimmer", "wav"],
	"salt_pour": ["equipment/salt_pour", "wav"],
	"holy_water_splash": ["equipment/holy_water_splash", "wav"],
	"crucifix_burn": ["equipment/crucifix_burn", "wav"],
	"stake_strike": ["equipment/stake_strike", "wav"],
	"melt_silver": ["equipment/melt_silver", "wav"],
	"camera_shutter": ["equipment/camera_shutter", "wav"],
	"emf_beep": ["equipment/emf_beep", "wav"],
	"emf_spike": ["equipment/emf_spike", "wav"],
	"thermometer_tick": ["equipment/thermometer_tick", "wav"],
	# evidence
	"pencil_scribble": ["evidence/journal_write", "wav"],
	"whisper_mimic": ["evidence/mimic_voice", "wav"],
	# entities
	"ghost_wail": ["entities/ghost_wail", "wav"],
	"poltergeist_bang": ["entities/poltergeist_bang", "wav"],
	"hunt_start": ["entities/hunt_start", "wav"],
	"hunt_loop": ["entities/hunt_loop", "ogg"],
	"vampire_hiss": ["entities/vampire_hiss", "wav"],
	"werewolf_howl": ["entities/werewolf_howl", "wav"],
	"werewolf_growl": ["entities/werewolf_growl", "wav"],
	"shapeshift": ["entities/shapeshift", "wav"],
	"cat_meow": ["entities/cat_meow", "wav"],
	"harbinger_arrival": ["entities/harbinger_arrival", "wav"],
	"blight_ping": ["entities/blightness_ping", "wav"],
	"crawl_drag": ["entities/crawler_drag", "wav"],
	"music_box": ["entities/lost_one_music_box", "wav"],
	"sea_whisper": ["entities/drowned_sailor_whisper", "wav"],
	"water_splash": ["entities/drowned_sailor_emerge", "wav"],
	"plague_breath": ["entities/plague_doctor_breath", "wav"],
	"bottle_clink": ["entities/plague_doctor_bottles", "wav"],
	"reckless_reaction": ["entities/reckless_reaction", "wav"],
	"vanquish_success": ["entities/vanquish", "wav"],
	# environment
	"door_creak": ["environment/door_creak", "wav"],
	"door_slam": ["environment/door_slam", "wav"],
	"candle_light": ["environment/flame_light", "wav"],
	"flame_snuff": ["environment/flame_snuff", "wav"],
	"ignite": ["environment/supernatural_ignite", "wav"],
	"furnace_roar": ["environment/furnace_roar", "wav"],
	"water_drip": ["environment/water_drip", "wav"],
	"wood_creak": ["environment/timber_creak", "wav"],
	"clock_toll": ["environment/clock_toll", "wav"],
	"nm_knock": ["environment/nightmare_knock", "wav"],
	"nm_drag": ["environment/nightmare_drag", "wav"],
	"critter_squish": ["environment/critter_squish", "wav"],
	# ambient (loops)
	"ambience_house": ["ambient/house_ambience", "ogg"],
	"music_menu": ["ambient/menu_music", "ogg"],
	# npc
	"npc_gasp": ["npc/gasp", "wav"],
	"npc_flee": ["npc/flee", "wav"],
	"scream_1": ["npc/scream_1", "wav"],
	"scream_2": ["npc/scream_2", "wav"],
	"scream_3": ["npc/scream_3", "wav"],
	# ui
	"ui_click": ["ui/click", "wav"],
	"ui_hover": ["ui/hover", "wav"],
	"results_win": ["ui/results_win", "wav"],
	"results_lose": ["ui/results_lose", "wav"],
}

## Candidate creator files for a cue, in lookup order: the single replacement
## (preferred format, then the other), then numbered variants _01 … _08.
static func candidates(id: String) -> Array:
	if not CUES.has(id):
		return []
	var stem: String = CREATOR_DIR + CUES[id][0]
	var fmts: Array = [CUES[id][1], "ogg" if CUES[id][1] == "wav" else "wav"]
	var out: Array = []
	for f in fmts:
		out.append(stem + "." + f)
	for i in range(1, MAX_VARIANTS + 1):
		for f in fmts:
			out.append(stem + "_%02d.%s" % [i, f])
	return out

## Loads a creator file. Imported files (editor, exported builds) load as normal
## resources; a file dropped in but not yet imported is read directly so a plain
## relaunch is enough while developing.
static func load_stream(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		var r = load(path)
		return r if r is AudioStream else null
	if not FileAccess.file_exists(path):
		return null
	if path.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(path)
	return _wav_from_file(path)

## Minimal RIFF/WAVE reader (8/16-bit PCM, mono or stereo) for un-imported files.
static func _wav_from_file(path: String) -> AudioStreamWAV:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() < 44 or f.get_buffer(4).get_string_from_ascii() != "RIFF":
		return null
	f.get_32()
	if f.get_buffer(4).get_string_from_ascii() != "WAVE":
		return null
	var channels := 1
	var rate := 44100
	var bits := 16
	var data := PackedByteArray()
	while f.get_position() + 8 <= f.get_length():
		var tag := f.get_buffer(4).get_string_from_ascii()
		var size := f.get_32()
		var start := f.get_position()
		if tag == "fmt ":
			if f.get_16() != 1:
				return null   # compressed WAV: import it in the editor instead
			channels = f.get_16()
			rate = f.get_32()
			f.get_32()
			f.get_16()
			bits = f.get_16()
		elif tag == "data":
			data = f.get_buffer(size)
		f.seek(start + size + (size % 2))
	if data.is_empty() or not (bits in [8, 16]):
		return null
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	if bits == 8:
		for i in data.size():
			data[i] = (data[i] + 128) % 256   # WAV 8-bit is unsigned; Godot expects signed
	s.stereo = channels == 2
	s.mix_rate = rate
	s.data = data
	return s
