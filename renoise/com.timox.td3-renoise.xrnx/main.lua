--[[
TD-3 Pattern Editor – Renoise scripting tool.

Editor grid layout, top to bottom:
  toolbar      : slot picker, MIDI out, import-from-renoise, send, preview
  OCT          : 4 rows (octaves 1..4, mutually exclusive per step; empty
                  column = default to octave 2)
  PITCH        : 12 rows (B..C, top to bottom). One cell per column at most.
                  An empty PITCH column means the step is a REST.
  SLIDE        : per-step toggle
  ACCENT       : per-step toggle
  SysEx hex    : multiline read-only

Step → TD-3 storage = ((octave or 2) - 1) * 12 + (semitone - 1) + 12,
clamped to [0x0C, 0x30].
]]

local td3 = require "td3"

local PITCH_NAMES = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}

-- Le hardware TD-3 est figé à 16 pas, sans FX par pas : tout le chemin
-- SysEx / .syx / .seq / .yml reste donc sur HW_STEPS = 16, inchangé.
-- Le mode "MIDI-live" (TD-3 = module de son) n'a pas ces limites : la
-- grille peut aller jusqu'à MAX_STEPS = 32 et porter des FX par pas
-- (ratchet, cutoff CC74, microtiming, gate). Ces FX et les pas > 16 ne
-- sont JAMAIS écrits en mémoire TD-3 — ils ne vivent qu'en preview /
-- export piste Renoise.
local HW_STEPS    = 16
local MAX_STEPS   = 32
local STEPS       = HW_STEPS  -- alias historique (chemin hardware uniquement)

-- Valeurs FX neutres : un pattern 16 pas sans FX rejoue exactement comme
-- avant (ratchet 1, pas de CC cutoff, pas de décalage, note tenue).
local FX_DEFAULT  = { ratchet = 1, cutoff = -1, delay = 0, gate = 100 }

-- Visual constants -----------------------------------------------------------
local CELL_W      = 22
local CELL_H      = 14
local LABEL_W     = 56
local COLOR_OFF   = {0xC8, 0xC2, 0xB0}   -- beige
local COLOR_ON    = {0x90, 0x30, 0x28}   -- dark red
local COLOR_GROUP = {0x55, 0x55, 0x55}   -- group separator

-- Preferences ---------------------------------------------------------------

local PREFS = renoise.Document.create("Td3RenoisePrefs") {
  midi_out_name        = "",
  midi_in_name         = "",
  midi_channel         = 1,    -- 1..16
  group_index          = 1,    -- 1..4 → I..IV
  pattern_index        = 1,    -- 1..16 → 1A..8B
  triplet              = false,
  normal_velocity      = 80,
  accent_velocity      = 100,
  preview_step_ms      = 125,  -- 1/16 note at 120 BPM
  step_rate_index      = 3,    -- 1..5 → 1/4, 1/8, 1/16, 1/32, 1/64
  loop                 = false,
  sync_bpm             = true, -- override step_ms with Renoise BPM
  filter_cutoff        = 64,   -- CC 74 last value
  -- Pattern state is persisted as a flat string of 16 step records:
  --   "o:s:a:l" per step, joined by ";". o ∈ 0..4 (0=rest), s ∈ 0..12 (1..12
  --   for C..B), a/l ∈ 0/1.
  pattern_state        = "",

  -- Mode MIDI-live (dialogue séparé) : état indépendant. Record étendu
  -- "o:s:a:l:r:c:d:g" (ratchet, cutoff CC74 ou -1, delay ms, gate %),
  -- MAX_STEPS pas, jamais écrit en mémoire TD-3.
  live_pattern_state   = "",
  live_length          = 16,   -- 16 ou 32
  live_step_rate_index = 3,
  live_loop            = true,
  live_sync_bpm        = true,
  live_step_ms         = 125,
  live_normal_velocity = 80,
  live_accent_velocity = 110,
}
renoise.tool().preferences = PREFS

-- Pattern model -------------------------------------------------------------

local function new_steps()
  local t = {}
  for i = 1, STEPS do
    t[i] = { oct = 0, semi = 0, accent = false, slide = false }
  end
  return t
end

local function steps_to_string(steps)
  local parts = {}
  for i = 1, STEPS do
    local s = steps[i]
    parts[i] = string.format("%d:%d:%d:%d",
      s.oct, s.semi, s.accent and 1 or 0, s.slide and 1 or 0)
  end
  return table.concat(parts, ";")
end

local function steps_from_string(str)
  local steps = new_steps()
  if not str or str == "" then return steps end
  local i = 1
  for chunk in string.gmatch(str, "[^;]+") do
    local o, s, a, l = chunk:match("(%d+):(%d+):(%d+):(%d+)")
    if o and i <= STEPS then
      steps[i] = {
        oct    = tonumber(o),
        semi   = tonumber(s),
        accent = a == "1",
        slide  = l == "1",
      }
    end
    i = i + 1
  end
  return steps
end

local function step_to_td3(s)
  if s.semi == 0 then
    -- Rest: stash the default placeholder pitch (firmware's idle value).
    return { pitch = td3.DEFAULT_PITCH, rest = true,
             accent = s.accent, slide = s.slide }
  end
  local oct  = s.oct > 0 and s.oct or 2  -- default octave when none picked
  local midi = (oct + 1) * 12 + (s.semi - 1)  -- (oct-1)*12 + (semi-1) + 24
  -- La TD-3 ne couvre que MIDI 24..60 (C1..C4 inclus). Si on déborde,
  -- on descend (ou monte) d'une octave pour préserver la pitch class —
  -- au lieu de clamper bêtement à C4 (= toutes les notes hors range
  -- devenaient des C, d'où G#4 → C4 dans le bug reporté).
  while midi > 60 do midi = midi - 12 end
  while midi < 24 do midi = midi + 12 end
  return {
    pitch  = td3.midi_to_storage(midi),
    rest   = false,
    accent = s.accent,
    slide  = s.slide,
    tie    = false,
  }
end

-- Importing from the currently selected Renoise pattern --------------------

local function pick_note_column(line)
  for i = 1, #line.note_columns do
    local c = line.note_columns[i]
    if c and c.note_value < 121 then return c end
  end
  return line.note_columns[1]
end

local function import_from_renoise(steps, accent_threshold, octave_shift)
  local song    = renoise.song()
  local pattern = song:pattern(song.selected_pattern_index)
  local track   = pattern:track(song.selected_track_index)
  for i = 1, STEPS do
    local line = track:line(i)
    local nc = pick_note_column(line)
    if nc and nc.note_value < 120 then
      -- Renoise note_value (= MIDI - 12) → octave + semitone within TD-3 range
      local nv  = nc.note_value + octave_shift * 12
      local oct = math.floor(nv / 12)
      local semi = (nv % 12) + 1
      if oct < 1 then oct = 1 elseif oct > 4 then oct = 4; semi = 1 end
      local acc = nc.volume_value < 128 and nc.volume_value >= accent_threshold
      local sli = false
      for ec = 1, #line.effect_columns do
        local fx = line.effect_columns[ec]
        if fx.number_string == "0G" or fx.number_string == "G0" then
          sli = true
        end
      end
      steps[i] = { oct = oct, semi = semi, accent = acc, slide = sli }
    else
      steps[i] = { oct = 0, semi = 0, accent = false, slide = false }
    end
  end
end

-- MIDI helpers --------------------------------------------------------------

local _midi_out, _midi_out_name = nil, nil

local function get_midi_out(name)
  if _midi_out_name ~= name then
    if _midi_out then _midi_out:close() end
    _midi_out, _midi_out_name = nil, nil
  end
  if not _midi_out and name and name ~= "" then
    _midi_out = renoise.Midi.create_output_device(name)
    _midi_out_name = name
  end
  return _midi_out
end

local function send_sysex(out, msg)
  -- Renoise's MidiOutputDevice:send() accepts SysEx as long as the message
  -- is framed with 0xF0..0xF7. The probe-for-method pattern triggers an
  -- __index error on unknown properties, so just call :send().
  out:send(msg)
end


-- ---------------------------------------------------------------------------
-- MIDI input + TD-3 SysEx config probe
-- ---------------------------------------------------------------------------

local _midi_in, _midi_in_name = nil, nil
local _midi_in_handler = nil

local function get_midi_in(name, sysex_cb)
  -- Always replace the active handler — opening the device only once and
  -- keeping a stable internal callback that dispatches to the current
  -- _midi_in_handler avoids ever silently dropping a new callback.
  _midi_in_handler = sysex_cb
  if _midi_in_name ~= name then
    if _midi_in then _midi_in:close() end
    _midi_in, _midi_in_name = nil, nil
  end
  if not _midi_in and name and name ~= "" then
    _midi_in = renoise.Midi.create_input_device(name, nil, function(msg)
      if _midi_in_handler then _midi_in_handler(msg) end
    end)
    _midi_in_name = name
  end
  return _midi_in
end

-- Helpers to build the request SysEx frames (mirroring src/td3/config.py).
local SYX_HDR = { 0xF0, 0x00, 0x20, 0x32, 0x00, 0x01, 0x0A }

local function sysex_frame(opcode, ...)
  local t = {}
  for _, b in ipairs(SYX_HDR) do table.insert(t, b) end
  table.insert(t, opcode)
  for _, b in ipairs({...}) do table.insert(t, b) end
  table.insert(t, 0xF7)
  return t
end

local function parse_config_response(msg)
  -- Expected: F0 00 20 32 00 01 0A 76 <10 bytes> F7  (19 bytes total)
  if #msg < 19 or msg[8] ~= 0x76 then return nil end
  return {
    midi_output_channel       = msg[9]  + 1,
    midi_input_channel        = msg[10] + 1,
    midi_input_transpose      = msg[11] - 12,
    pitch_bend_semitones      = msg[12],
    key_priority              = msg[13],
    multi_trigger             = msg[14] == 1,
    clock_trigger_polarity    = msg[15],
    clock_trigger_rate        = msg[16],
    clock_source              = msg[17],
    accent_velocity_threshold = msg[18],
  }
end

local function parse_fw_response(msg)
  -- F0 00 20 32 00 01 0A 09 00 <maj> <min> <rev> F7
  if #msg < 13 or msg[8] ~= 0x09 then return nil end
  return string.format("%d.%d.%d", msg[10], msg[11], msg[12])
end

local CLOCK_SRC  = {"Internal", "MIDI DIN", "MIDI USB", "Trigger"}
local KEY_PRIO   = {"Low", "High", "Last"}

-- Step rate options: each step lasts the given musical subdivision when
-- syncing to Renoise's BPM. step_ms = 15000 / (BPM × mult).
-- mult = 1 → step = 1/16 (default). mult = 2 → step = 1/32 (twice as fast).
-- The 16-step pattern then spans 4 quarters (at 1/16), 2 quarters (at 1/32),
-- or 8 quarters (at 1/8), etc. — always synced, just at a finer or coarser
-- subdivision than Renoise's row grid.
local STEP_RATES = {
  { label = "1/4 ×0.25", mult = 0.25 },
  { label = "1/8 ×0.5",  mult = 0.5  },
  { label = "1/16 ×1",   mult = 1    },
  { label = "1/32 ×2",   mult = 2    },
  { label = "1/64 ×4",   mult = 4    },
}

--- Send the SysEx "Set clock source" (opcode 0x1B). Returns true on success.
local function set_clock_source(value)
  local out = get_midi_out(PREFS.midi_out_name.value)
  if not out then renoise.app():show_warning("Pas de port MIDI OUT.") return false end
  out:send(sysex_frame(0x1B, value))
  return true
end

--- Send the SysEx "Set accent velocity threshold" (opcode 0x1C, 0..127).
local function set_accent_threshold(value)
  local out = get_midi_out(PREFS.midi_out_name.value)
  if not out then renoise.app():show_warning("Pas de port MIDI OUT.") return false end
  value = math.max(0, math.min(127, value))
  out:send(sysex_frame(0x1C, value))
  return true
end

--- Convert a TD-3 storage pitch byte (12..48) to the grid's
-- {octave (1..4), semitone (1..12)} representation.
local function pitch_to_oct_semi(storage)
  storage = math.max(12, math.min(48, storage))
  return math.floor(storage / 12), (storage % 12) + 1
end

--- Recopie un pattern décodé (td3.decode_data) dans la grille de l'éditeur.
-- Partagé entre "Read TD-3" (SysEx live) et "Load .syx" (fichier local).
local function apply_decoded_to_steps(state_steps, decoded)
  PREFS.triplet.value = decoded.triplet
  for i = 1, td3.STEPS do
    local oct, semi = pitch_to_oct_semi(decoded.pitches[i])
    if decoded.rest_mask[i] then
      state_steps[i] = { oct = 0, semi = 0,
                         accent = decoded.accent[i] ~= 0,
                         slide  = decoded.slide[i]  ~= 0 }
    else
      state_steps[i] = { oct = oct, semi = semi,
                         accent = decoded.accent[i] ~= 0,
                         slide  = decoded.slide[i]  ~= 0 }
    end
  end
end

--- Pull a pattern from the TD-3 and fill the editor grid.
local function read_pattern_from_td3(state_steps, group, pat, on_done)
  local out = get_midi_out(PREFS.midi_out_name.value)
  if not out then renoise.app():show_warning("Pas de port MIDI OUT.") return end
  if PREFS.midi_in_name.value == "" then
    renoise.app():show_warning("Pas de port MIDI IN.") return
  end

  local got = nil
  get_midi_in(PREFS.midi_in_name.value, function(msg)
    if msg and msg[8] == 0x78 then
      local g, p, data = td3.parse_sysex_pattern(msg)
      if data then got = { group = g, pat = p, data = data } end
    end
  end)

  out:send(sysex_frame(0x77, group, pat))

  local timer
  timer = function()
    if renoise.tool():has_timer(timer) then renoise.tool():remove_timer(timer) end
    if not got then
      renoise.app():show_warning(string.format(
        "Pas de réponse de la TD-3 pour le slot %s / %s.",
        td3.GROUP_LABELS[group + 1],
        td3.format_pattern_label(pat)))
      return
    end
    local decoded = td3.decode_data(got.data)
    apply_decoded_to_steps(state_steps, decoded)
    if on_done then on_done(decoded) end
  end
  renoise.tool():add_timer(timer, 500)
end

local function check_td3_config(on_done)
  local out = get_midi_out(PREFS.midi_out_name.value)
  if not out then
    renoise.app():show_warning("Pas de port MIDI OUT sélectionné.")
    return
  end
  if PREFS.midi_in_name.value == "" then
    renoise.app():show_warning("Pas de port MIDI IN sélectionné (sortie MIDI de la TD-3).")
    return
  end

  local collected = {}
  local got_cfg, got_fw = nil, nil

  get_midi_in(PREFS.midi_in_name.value, function(msg)
    if not msg or #msg < 8 then return end
    if msg[8] == 0x76 then got_cfg = parse_config_response(msg) end
    if msg[8] == 0x09 then got_fw  = parse_fw_response(msg) end
  end)

  -- Send the two queries back-to-back.
  out:send(sysex_frame(0x08, 0))    -- request firmware version
  out:send(sysex_frame(0x75))       -- request full config

  -- Give the TD-3 ~500 ms to answer, then assemble the report.
  local fired = false
  local function finish()
    if fired then return end
    fired = true
    local lines = {}
    table.insert(lines, "=== Vérification TD-3 ===")
    if got_fw then
      table.insert(lines, "Firmware : " .. got_fw)
    else
      table.insert(lines, "Firmware : (pas de réponse — vérifier MIDI IN / câble)")
    end
    if got_cfg then
      table.insert(lines, string.format("Canal MIDI in/out : %d / %d",
        got_cfg.midi_input_channel, got_cfg.midi_output_channel))
      table.insert(lines, "Clock source : " ..
        (CLOCK_SRC[got_cfg.clock_source + 1] or "?"))
      table.insert(lines, "Key priority : " ..
        (KEY_PRIO[got_cfg.key_priority + 1] or "?"))
      table.insert(lines, "Multi-trigger : " .. tostring(got_cfg.multi_trigger))
      table.insert(lines, "Accent velocity threshold : " ..
        tostring(got_cfg.accent_velocity_threshold))
      table.insert(lines, "Transpose MIDI in : " ..
        tostring(got_cfg.midi_input_transpose))
      table.insert(lines, "Pitch Bend range : " ..
        tostring(got_cfg.pitch_bend_semitones))

      -- Warnings
      table.insert(lines, "")
      table.insert(lines, "--- Diagnostic ---")
      if got_cfg.clock_source == 0 then
        table.insert(lines, "⚠  Clock source = Internal : la TD-3 IGNORE les notes MIDI in. Mettez le sélecteur TIME MODE en MIDI ou USB.")
      else
        table.insert(lines, "✓  Clock source compatible MIDI in")
      end
      if got_cfg.midi_input_channel ~= PREFS.midi_channel.value then
        table.insert(lines, string.format(
          "⚠  Canal MIDI input TD-3 = %d, l'outil envoie sur %d → mismatch. Changez Ch dans la toolbar ou écrivez le canal de la TD-3 via SysEx.",
          got_cfg.midi_input_channel, PREFS.midi_channel.value))
      else
        table.insert(lines, string.format("✓  Canal MIDI = %d, cohérent",
          got_cfg.midi_input_channel))
      end
      if got_cfg.accent_velocity_threshold >
         math.min(PREFS.normal_velocity.value, PREFS.accent_velocity.value) then
        table.insert(lines, string.format(
          "ℹ  Accent threshold TD-3 = %d. Les notes envoyées avec vel < %d ne déclencheront PAS l'accent ; vel ≥ %d le déclenchera.",
          got_cfg.accent_velocity_threshold,
          got_cfg.accent_velocity_threshold,
          got_cfg.accent_velocity_threshold))
      end
    else
      table.insert(lines, "Config : (pas de réponse 0x76)")
    end
    if on_done then on_done(table.concat(lines, "\n")) end
  end

  -- Renoise add_timer fires at intervals; use a one-shot via remove inside.
  local timer
  timer = function()
    finish()
    if renoise.tool():has_timer(timer) then
      renoise.tool():remove_timer(timer)
    end
  end
  renoise.tool():add_timer(timer, 500)
end

-- All channel-voice messages use the user-selected MIDI channel (1..16).
-- `status_nibble` is the high nibble: 0x80=Note Off, 0x90=Note On, 0xB0=CC, etc.
local function send_short(out, status_nibble, d1, d2)
  local ch = (PREFS.midi_channel.value - 1) % 16
  out:send { status_nibble + ch, d1, d2 }
end

local function send_cc(out, cc, value)
  send_short(out, 0xB0, cc, math.max(0, math.min(127, value)))
end

-- Preview audio --------------------------------------------------------------

local _preview_timer, _preview_state = nil, nil
local _transport_handler = nil

-- Forward declarations : Renoise tool strict mode interdit l'accès aux
-- variables non déclarées, et preview_stop appelle unwatch_renoise_transport
-- qui est défini plus bas.
local inhibit_td3_sequencer
local watch_renoise_transport
local unwatch_renoise_transport

local function all_notes_off(out)
  -- Note OFF pour toutes les pitches + CC 123 (All Notes Off) + CC 120
  -- (All Sound Off). On N'ENVOIE PAS de MIDI Stop (0xFC) : en clock
  -- source MIDI USB la TD-3 passe en "stopped" et ignore ensuite les
  -- notes/CC entrants (régression cutoff + slide constatée).
  if not out then return end
  for n = 0, 127 do
    send_short(out, 0x80, n, 0x40)
  end
  send_short(out, 0xB0, 123, 0)
  send_short(out, 0xB0, 120, 0)
end

local function preview_stop()
  if _preview_timer and renoise.tool():has_timer(_preview_timer) then
    renoise.tool():remove_timer(_preview_timer)
  end
  _preview_timer = nil
  unwatch_renoise_transport()  -- no-op si jamais armé
  if _preview_state and _preview_state.out then
    all_notes_off(_preview_state.out)
  end
  _preview_state = nil
end

-- Quand Renoise est en lecture et qu'il envoie MIDI Clock Master vers le
-- port TD-3, la TD-3 reçoit aussi MIDI Start (FA) et lance son séquenceur
-- interne en parallèle de nos Note On — d'où le mélange "pattern que je
-- ne connais pas" + nos notes. On neutralise en envoyant MIDI Stop (FC)
-- au démarrage du Preview, puis on hooke transport.playing : si
-- l'utilisateur relance Renoise pendant la prise, on re-Stop la TD-3.

function inhibit_td3_sequencer(out)
  if out then out:send { 0xFC } end  -- MIDI Real-Time Stop
end

function watch_renoise_transport(out)
  if _transport_handler then return end
  local song = renoise.song()
  _transport_handler = function()
    if song.transport.playing then
      inhibit_td3_sequencer(out)
    end
  end
  song.transport.playing_observable:add_notifier(_transport_handler)
end

function unwatch_renoise_transport()
  if not _transport_handler then return end
  local song = renoise.song()
  if song.transport.playing_observable:has_notifier(_transport_handler) then
    song.transport.playing_observable:remove_notifier(_transport_handler)
  end
  _transport_handler = nil
end


local function preview_start(get_step, step_ms, normal_vel, accent_vel, loop, out)
  preview_stop()
  -- NB : on n'envoie PLUS de MIDI Stop (0xFC) automatique ici. En clock
  -- source MIDI USB, la TD-3 passe en "stopped" sur 0xFC et ignore alors
  -- les notes ET les CC entrants → on perdait cutoff + slide. Pour éviter
  -- que le séquenceur interne TD-3 se lance en parallèle, désactiver
  -- "MIDI Clock Master Output" vers le port TD-3 dans
  -- Edit → Preferences → MIDI côté Renoise (solution propre et permanente).
  -- active_notes : pile des Note On envoyés sans Note Off correspondant.
  -- Une chaîne de slides empile plusieurs notes sans les relâcher pour
  -- garder le gate TD-3 ouvert (= legato). Sur le premier step non-slide
  -- ou rest, on relâche TOUS les empilés d'un coup pour que l'enveloppe
  -- TD-3 retrigge sur la nouvelle attaque.
  _preview_state = { out = out, step = 0, active_notes = {},
                     get_step = get_step, loop = loop }

  local function release_all(st)
    for _, n in ipairs(st.active_notes) do
      send_short(st.out, 0x80, n, 0x40)
    end
    st.active_notes = {}
  end

  _preview_timer = function()
    local st = _preview_state
    if not st then return end
    if st.step >= STEPS then
      if st.loop then
        st.step = 0
      else
        release_all(st)
        preview_stop(); return
      end
    end
    local s = st.get_step(st.step + 1)
    if s and not s.rest and s.pitch then
      local midi = td3.storage_to_midi(s.pitch)
      local vel  = s.accent and accent_vel or normal_vel
      if s.slide and #st.active_notes > 0 then
        local last = st.active_notes[#st.active_notes]
        if midi == last then
          -- Slide vers la même tonalité : pas de glissement, pas de
          -- retrigger d'enveloppe attendu (= effet "tied note" / sustain
          -- TB-303). On n'envoie aucun Note On pour éviter que la TD-3
          -- ne re-déclenche l'enveloppe.
        else
          -- Slide / legato vers une nouvelle pitch : Note On empilé sans
          -- relâcher. Gate ouvert, portamento jusqu'à la nouvelle pitch.
          send_short(st.out, 0x90, midi, vel)
          table.insert(st.active_notes, midi)
        end
      else
        -- Step non-slide : libère TOUT (chaîne de slides précédente
        -- incluse), puis attaque la nouvelle note proprement.
        release_all(st)
        send_short(st.out, 0x90, midi, vel)
        table.insert(st.active_notes, midi)
      end
    else
      -- Rest : libère tout, gate fermé.
      release_all(st)
    end
    st.step = st.step + 1
  end
  renoise.tool():add_timer(_preview_timer, step_ms)
end

-- Build the SysEx for the current state ------------------------------------

local function build_sysex(steps, group_index, pattern_index, triplet)
  local td3_steps = {}
  for i = 1, STEPS do td3_steps[i] = step_to_td3(steps[i]) end
  local data = td3.encode_data(td3_steps, triplet, STEPS)
  return td3.to_sysex(group_index - 1, pattern_index - 1, data)
end

-- Bibliothèque locale : lecture / écriture de patterns en .syx, sans
-- passer par l'utilitaire Python. Le tool Renoise est ainsi autonome —
-- td3.lua produit et relit le SysEx natif de la TD-3.

local function bytes_to_binstr(arr)
  local t = {}
  for i = 1, #arr do t[i] = string.char(arr[i] % 256) end
  return table.concat(t)
end

local function binstr_to_bytes(str)
  local t = {}
  for i = 1, #str do t[i] = str:byte(i) end
  return t
end

-- Extrait la première trame F0..F7 qui est un dump pattern (opcode 0x78).
-- Tolère un .syx contenant plusieurs messages (config, firmware, etc.).
local function extract_pattern_sysex(bytes)
  local n, i = #bytes, 1
  while i <= n do
    if bytes[i] == 0xF0 then
      for j = i, n do
        if bytes[j] == 0xF7 then
          local frame = {}
          for k = i, j do frame[#frame + 1] = bytes[k] end
          if frame[8] == td3.OP_WRITE then return frame end
          i = j
          break
        end
      end
    end
    i = i + 1
  end
  return nil
end

local function chunk_hex(arr, per_line)
  per_line = per_line or 16
  local out, line = {}, {}
  for i, b in ipairs(arr) do
    table.insert(line, string.format("%02X", b))
    if i % per_line == 0 then
      table.insert(out, table.concat(line, " ")); line = {}
    end
  end
  if #line > 0 then table.insert(out, table.concat(line, " ")) end
  return table.concat(out, "\n")
end

-- Dialog --------------------------------------------------------------------

local _dialog = nil

local function group_items() return td3.GROUP_LABELS end
local function pattern_items()
  local t = {}
  for n = 0, 15 do table.insert(t, td3.format_pattern_label(n)) end
  return t
end

local function show_dialog()
  local vb    = renoise.ViewBuilder()
  local state = { steps = steps_from_string(PREFS.pattern_state.value) }
  local cells = { oct = {}, pitch = {}, accent = {}, slide = {} }
  local hex_view, status_view

  local function persist()
    PREFS.pattern_state.value = steps_to_string(state.steps)
  end

  local function rebuild_sysex_view()
    local sysex = build_sysex(state.steps,
      PREFS.group_index.value, PREFS.pattern_index.value, PREFS.triplet.value)
    state.sysex = sysex
    hex_view.text = chunk_hex(sysex, 16)
    status_view.text = string.format("Slot : %s / %s   |   SysEx : %d octets",
      td3.GROUP_LABELS[PREFS.group_index.value],
      td3.format_pattern_label(PREFS.pattern_index.value - 1),
      #sysex)
  end

  local function paint_cell(view, active)
    view.color = active and COLOR_ON or COLOR_OFF
  end

  local function repaint_step(i)
    local s = state.steps[i]
    for o = 1, 4 do paint_cell(cells.oct[o][i],  s.oct == o)    end
    for p = 1, 12 do paint_cell(cells.pitch[p][i], s.semi == p) end
    paint_cell(cells.accent[i], s.accent)
    paint_cell(cells.slide[i],  s.slide)
  end

  local function repaint_all()
    for i = 1, STEPS do repaint_step(i) end
  end

  -- Record helper : pilote le Sample Recorder Renoise via l'API 6.2
  -- (start_sample_recording / stop_sample_recording + flag sync). Le panel
  -- doit être visible : on l'ouvre s'il ne l'est pas. Renoise quantize le
  -- record sur la frontière de pattern courante quand sync_enabled est on.
  local function start_recording()
    local app = renoise.app()
    local song = renoise.song()
    local ok, err = pcall(function()
      app.window.sample_record_dialog_is_visible = true
      song.transport.sample_recording_sync_enabled = true
      song.transport:start_sample_recording()
    end)
    if not ok then
      renoise.app():show_warning("API Renoise 6.2+ requise pour piloter le Sample Recorder.\n\n" ..
        "Erreur : " .. tostring(err))
      return false
    end
    return true
  end

  local function stop_recording()
    pcall(function() renoise.song().transport:stop_sample_recording() end)
  end

  -- Two preview launchers: immediate or aligned to Renoise's next pattern
  -- boundary. Sync=line 0 of the playing pattern.
  local function launch_preview(synced)
    local out = get_midi_out(PREFS.midi_out_name.value)
    if not out then renoise.app():show_warning("Aucun port MIDI valide.") return end
    local step_ms = PREFS.preview_step_ms.value
    if PREFS.sync_bpm.value then
      local rate = STEP_RATES[PREFS.step_rate_index.value] or STEP_RATES[3]
      -- Binaire : 16 steps / mesure = 1/16 par step = 15000/BPM ms
      -- Triplet : 12 steps / mesure = triplet 1/8 par step = 20000/BPM ms
      -- (chaque step ternaire = 4/3 d'un step binaire 1/16)
      local base = 15000 / renoise.song().transport.bpm
      if PREFS.triplet.value then base = base * 4 / 3 end
      step_ms = math.floor(base / rate.mult + 0.5)
    end
    local function read_step(i) return step_to_td3(state.steps[i]) end
    local function go()
      preview_start(read_step, step_ms,
                    PREFS.normal_velocity.value,
                    PREFS.accent_velocity.value,
                    PREFS.loop.value, out)
    end
    if not synced or not renoise.song().transport.playing then
      go(); return
    end
    -- Wait until Renoise's playback wraps to the next pattern. We track
    -- the previous line and fire when we detect line wrap (line decreased
    -- or sequence index changed). Initial line is captured so we don't
    -- mistake "we're already past line 1" for "we just hit it".
    renoise.app():show_status("TD-3 preview en attente du prochain pattern Renoise...")
    local song = renoise.song()
    local prev = { seq = song.transport.playback_pos.sequence,
                   line = song.transport.playback_pos.line }
    local started = os.clock()
    local poll
    poll = function()
      if not song.transport.playing then
        if renoise.tool():has_timer(poll) then renoise.tool():remove_timer(poll) end
        go(); return
      end
      local pos = song.transport.playback_pos
      local wrapped = (pos.sequence ~= prev.seq) or (pos.line < prev.line)
      prev.seq, prev.line = pos.sequence, pos.line
      if wrapped then
        if renoise.tool():has_timer(poll) then renoise.tool():remove_timer(poll) end
        go(); return
      end
      -- Safety : after 30s of waiting, give up and fire anyway.
      if os.clock() - started > 30 then
        if renoise.tool():has_timer(poll) then renoise.tool():remove_timer(poll) end
        renoise.app():show_status("Sync timeout — démarrage forcé du preview TD-3.")
        go()
      end
    end
    renoise.tool():add_timer(poll, 10)
  end

  local function on_change()
    persist(); rebuild_sysex_view()
  end

  -- Transpose tous les steps non-rest de `delta` demi-tons, en clampant
  -- à la plage TD-3 (C1..C4 = index absolu 0..36). idx = (oct-1)*12 +
  -- (semi-1) ; on borne avant de re-décomposer en oct/semi.
  local function transpose_all(delta)
    local clamped = false
    for i = 1, STEPS do
      local s = state.steps[i]
      if s.semi > 0 then
        local oct = s.oct > 0 and s.oct or 2
        local idx = (oct - 1) * 12 + (s.semi - 1) + delta
        if idx < 0 then idx = 0; clamped = true end
        if idx > 36 then idx = 36; clamped = true end
        s.oct  = math.floor(idx / 12) + 1
        s.semi = (idx % 12) + 1
      end
    end
    repaint_all()
    persist(); rebuild_sysex_view()
    if clamped then
      renoise.app():show_status(
        "Transpose : certaines notes ont buté sur les bornes C1/C4")
    end
  end

  -- Bibliothèque locale -----------------------------------------------------
  local function save_pattern_file()
    local path = renoise.app():prompt_for_filename_to_write(
      "syx", "Enregistrer le pattern (.syx)")
    if not path or path == "" then return end
    local sysex = build_sysex(state.steps, PREFS.group_index.value,
                              PREFS.pattern_index.value, PREFS.triplet.value)
    local f, err = io.open(path, "wb")
    if not f then
      renoise.app():show_warning("Écriture impossible : " .. tostring(err))
      return
    end
    f:write(bytes_to_binstr(sysex))
    f:close()
    renoise.app():show_status("Pattern enregistré : " .. path)
  end

  local function load_pattern_file()
    local path = renoise.app():prompt_for_filename_to_read(
      { "syx" }, "Charger un pattern (.syx)")
    if not path or path == "" then return end
    local f, err = io.open(path, "rb")
    if not f then
      renoise.app():show_warning("Lecture impossible : " .. tostring(err))
      return
    end
    local raw = f:read("*a")
    f:close()
    local frame = extract_pattern_sysex(binstr_to_bytes(raw))
    if not frame then
      renoise.app():show_warning(
        "Aucun dump pattern TD-3 (SysEx 0x78) trouvé dans ce fichier .syx.")
      return
    end
    local g, p, data = td3.parse_sysex_pattern(frame)
    if not data then
      renoise.app():show_warning("SysEx pattern invalide : " .. tostring(p))
      return
    end
    apply_decoded_to_steps(state.steps, td3.decode_data(data))
    repaint_all(); on_change()
    renoise.app():show_status(string.format(
      "Pattern chargé (%s) — slot d'origine %s / %s",
      path, td3.GROUP_LABELS[g + 1] or "?", td3.format_pattern_label(p)))
  end

  -- Données brutes du pattern courant (bloc 112 octets) à partir de la grille.
  local function current_data()
    local td3_steps = {}
    for i = 1, STEPS do td3_steps[i] = step_to_td3(state.steps[i]) end
    return td3.encode_data(td3_steps, PREFS.triplet.value, STEPS)
  end

  local function read_file_bytes(extensions, title)
    local path = renoise.app():prompt_for_filename_to_read(extensions, title)
    if not path or path == "" then return nil end
    local f, err = io.open(path, "rb")
    if not f then
      renoise.app():show_warning("Lecture impossible : " .. tostring(err))
      return nil
    end
    local raw = f:read("*a"); f:close()
    return raw, path
  end

  local function write_file_bytes(ext, title, binstr)
    local path = renoise.app():prompt_for_filename_to_write(ext, title)
    if not path or path == "" then return end
    local f, err = io.open(path, "wb")
    if not f then
      renoise.app():show_warning("Écriture impossible : " .. tostring(err))
      return
    end
    f:write(binstr); f:close()
    renoise.app():show_status("Enregistré : " .. path)
  end

  local function load_seq_file()
    local raw, path = read_file_bytes({ "seq" }, "Charger un pattern (.seq)")
    if not raw then return end
    local data, e2 = td3.read_seq(binstr_to_bytes(raw))
    if not data then
      renoise.app():show_warning("Fichier .seq invalide : " .. tostring(e2))
      return
    end
    apply_decoded_to_steps(state.steps, td3.decode_data(data))
    repaint_all(); on_change()
    renoise.app():show_status("Pattern .seq chargé : " .. path)
  end

  local function load_yaml_file()
    local raw, path = read_file_bytes({ "yml", "yaml" }, "Charger un pattern (.yml)")
    if not raw then return end
    local ok, decoded = pcall(td3.parse_yaml_pattern, raw)
    if not ok or not decoded then
      renoise.app():show_warning("YAML illisible : " .. tostring(decoded))
      return
    end
    apply_decoded_to_steps(state.steps, decoded)
    repaint_all(); on_change()
    renoise.app():show_status("Pattern .yml chargé : " .. path)
  end

  local function save_seq_file()
    write_file_bytes("seq", "Enregistrer le pattern (.seq)",
      bytes_to_binstr(td3.write_seq(current_data())))
  end

  local function save_yaml_file()
    local decoded = td3.decode_data(current_data())
    local yaml = td3.pattern_to_yaml(PREFS.group_index.value - 1,
      PREFS.pattern_index.value - 1, decoded)
    write_file_bytes("yml", "Enregistrer le pattern (.yml)", yaml)
  end

  -- TD-3 range : C1..C4 = MIDI 24..60. La 4e octave ne couvre que C —
  -- toute autre note à OCT 4 déborde et serait clampée. On corrige donc
  -- automatiquement les combinaisons invalides à la saisie pour que ce
  -- que l'utilisateur voit dans la grille corresponde à ce qui sera
  -- réellement stocké sur la TD-3.
  local function note_name(semi)  -- semi 1..12 → "C", "C#", ... "B"
    return PITCH_NAMES[semi] or "?"
  end

  -- Click handlers
  local function toggle_oct(step, o)
    local s = state.steps[step]
    s.oct = (s.oct == o) and 0 or o
    if s.oct == 4 and s.semi > 1 then
      local was = note_name(s.semi)
      s.semi = 1  -- force à C
      renoise.app():show_status(string.format(
        "Step %d : OCT 4 ne couvre que C sur la TD-3, %s ramené à C",
        step, was))
    end
    repaint_step(step); on_change()
  end

  local function toggle_pitch(step, p)
    local s = state.steps[step]
    s.semi = (s.semi == p) and 0 or p
    if s.oct == 4 and s.semi > 1 then
      s.oct = 3  -- bascule sur l'octave la plus haute supportée
      renoise.app():show_status(string.format(
        "Step %d : %s @ OCT 4 hors range, basculé à OCT 3",
        step, note_name(s.semi)))
    end
    repaint_step(step); on_change()
  end

  local function toggle_accent(step)
    state.steps[step].accent = not state.steps[step].accent
    repaint_step(step); on_change()
  end

  local function toggle_slide(step)
    state.steps[step].slide = not state.steps[step].slide
    repaint_step(step); on_change()
  end

  -- Build rows ---------------------------------------------------------------
  local function make_cell(notifier_fn)
    return vb:button {
      width = CELL_W, height = CELL_H,
      color = COLOR_OFF,
      notifier = notifier_fn,
    }
  end

  local function group_spacer()
    return vb:space { width = 4 }
  end

  local function row_with_cells(label, store, click_factory)
    local items = { vb:text { text = label, width = LABEL_W, font = "mono" } }
    for s = 1, STEPS do
      local btn = make_cell(click_factory(s))
      store[s] = btn
      table.insert(items, btn)
      if s % 4 == 0 and s < STEPS then table.insert(items, group_spacer()) end
    end
    return vb:row(items)
  end

  -- OCT rows (top to bottom: 4..1, so highest octave on top)
  local oct_rows = {}
  for o = 4, 1, -1 do
    cells.oct[o] = {}
    local items = { vb:text { text = "OCT " .. o, width = LABEL_W, font = "mono" } }
    for s = 1, STEPS do
      local cell = make_cell(function() toggle_oct(s, o) end)
      cells.oct[o][s] = cell
      table.insert(items, cell)
      if s % 4 == 0 and s < STEPS then table.insert(items, group_spacer()) end
    end
    table.insert(oct_rows, vb:row(items))
  end

  -- PITCH rows (top to bottom: B..C, so highest pitch on top)
  local pitch_rows = {}
  for p = 12, 1, -1 do
    cells.pitch[p] = {}
    local items = { vb:text { text = PITCH_NAMES[p], width = LABEL_W, font = "mono" } }
    for s = 1, STEPS do
      local cell = make_cell(function() toggle_pitch(s, p) end)
      cells.pitch[p][s] = cell
      table.insert(items, cell)
      if s % 4 == 0 and s < STEPS then table.insert(items, group_spacer()) end
    end
    table.insert(pitch_rows, vb:row(items))
  end

  -- SLIDE / ACCENT rows
  local slide_row  = row_with_cells("SLIDE",  cells.slide,  function(s) return function() toggle_slide(s)  end end)
  local accent_row = row_with_cells("ACCENT", cells.accent, function(s) return function() toggle_accent(s) end end)

  -- Toolbar -----------------------------------------------------------------
  hex_view    = vb:multiline_text { width = 16 * (CELL_W + 1) + LABEL_W,
                                    height = 90, font = "mono" }
  status_view = vb:text { text = "" }

  local midi_outs = renoise.Midi.available_output_devices()
  if #midi_outs == 0 then midi_outs = {"(no MIDI output detected)"} end
  local midi_ins = renoise.Midi.available_input_devices()
  if #midi_ins  == 0 then midi_ins  = {"(no MIDI input detected)"} end
  local function find_index(t, v)
    for i, x in ipairs(t) do if x == v then return i end end
    return nil
  end

  local toolbar1 = vb:row {
    vb:text { text = "Slot", width = 40 },
    vb:popup { items = group_items(), value = PREFS.group_index.value,
               notifier = function(v) PREFS.group_index.value = v; rebuild_sysex_view() end },
    vb:popup { items = pattern_items(), value = PREFS.pattern_index.value,
               notifier = function(v) PREFS.pattern_index.value = v; rebuild_sysex_view() end },
    vb:checkbox { value = PREFS.triplet.value,
                  notifier = function(v) PREFS.triplet.value = v; rebuild_sysex_view() end },
    vb:text { text = "triplet" },
  }

  local toolbar2 = vb:row {
    vb:text { text = "MIDI in/out", width = 70 },
    vb:popup { items = midi_ins,
               value = math.max(1, find_index(midi_ins, PREFS.midi_in_name.value) or 1),
               notifier = function(v) PREFS.midi_in_name.value = midi_ins[v] end,
               width = 160 },
    vb:popup { items = midi_outs,
               value = math.max(1, find_index(midi_outs, PREFS.midi_out_name.value) or 1),
               notifier = function(v) PREFS.midi_out_name.value = midi_outs[v] end,
               width = 160 },
    vb:text { text = "  Ch" },
    vb:valuebox { min = 1, max = 16, value = PREFS.midi_channel.value,
                  notifier = function(v) PREFS.midi_channel.value = v end },
    vb:text { text = "  Step ms" },
    vb:valuebox { min = 20, max = 1000, value = PREFS.preview_step_ms.value,
                  notifier = function(v) PREFS.preview_step_ms.value = v end },
    vb:text { text = "  Vel" },
    vb:valuebox { min = 1, max = 127, value = PREFS.normal_velocity.value,
                  notifier = function(v) PREFS.normal_velocity.value = v end },
    vb:text { text = "/ acc" },
    vb:valuebox { min = 1, max = 127, value = PREFS.accent_velocity.value,
                  notifier = function(v) PREFS.accent_velocity.value = v end },
  }

  -- Live filter cutoff (CC 74) — the only sound-shaping CC officially
  -- documented for the TD-3. Slider sends a CC message as you drag it.
  local cutoff_value_view = vb:text { text = tostring(PREFS.filter_cutoff.value), width = 28 }
  -- TD-3 config write : clock source + accent threshold via SysEx.
  -- Permet de contourner le sélecteur de clock source de la façade
  -- quand on ne sait pas le manipuler (combinaison de touches non
  -- évidente, mode caché du firmware…).
  local toolbar_cfg = vb:row {
    vb:text { text = "Clock source", width = 100 },
    vb:popup {
      items = CLOCK_SRC,
      value = 3, -- default visual : "MIDI USB"
      notifier = function(v) set_clock_source(v - 1) end,
      width = 100,
    },
    vb:text { text = "  Accent thr" },
    vb:valuebox {
      min = 0, max = 127, value = 80,
      notifier = function(v) set_accent_threshold(v) end,
    },
    vb:button { text = "Re-check", width = 80,
                notifier = function()
                  check_td3_config(function(report)
                    renoise.app():show_prompt("Vérification TD-3", report, { "OK" })
                  end)
                end },
  }

  local toolbar_cutoff = vb:row {
    vb:text { text = "Cutoff (CC 74)", width = 100 },
    vb:slider {
      min = 0, max = 127, value = PREFS.filter_cutoff.value, width = 240,
      notifier = function(v)
        local iv = math.floor(v + 0.5)
        PREFS.filter_cutoff.value = iv
        cutoff_value_view.text = tostring(iv)
        local out = get_midi_out(PREFS.midi_out_name.value)
        if out then send_cc(out, 0x4A, iv) end
      end,
    },
    cutoff_value_view,
    vb:button { text = "Send", width = 60,
                notifier = function()
                  local out = get_midi_out(PREFS.midi_out_name.value)
                  if out then send_cc(out, 0x4A, PREFS.filter_cutoff.value) end
                end },
  }

  local toolbar3 = vb:row {
    vb:button { text = "Check TD-3", width = 100,
                notifier = function()
                  check_td3_config(function(report)
                    renoise.app():show_prompt("Vérification TD-3", report, { "OK" })
                  end)
                end },
    vb:button { text = "Read TD-3", width = 90,
                notifier = function()
                  read_pattern_from_td3(state.steps,
                    PREFS.group_index.value - 1,
                    PREFS.pattern_index.value - 1,
                    function() repaint_all(); on_change() end)
                end },
    vb:button { text = "Clear", width = 70,
                notifier = function() state.steps = new_steps(); repaint_all(); on_change() end },
    vb:button { text = "Import depuis Renoise", width = 170,
                notifier = function()
                  import_from_renoise(state.steps, 0x60, -1)
                  repaint_all(); on_change()
                end },
    vb:button { text = "▶ Preview", width = 90,
                notifier = function() launch_preview(false) end },
    vb:button { text = "▶ Sync",    width = 70,
                notifier = function() launch_preview(true) end,
                tooltip = "Attend la prochaine frontière de pattern Renoise avant de lancer le loop. À coupler avec Sample Recorder en Sync=Pattern pour une prise calée." },
    vb:button { text = "⏺ Bounce",  width = 80,
                tooltip = "Ouvre le Sample Recorder Renoise en mode Sync=Pattern, l'arme, puis lance Preview synchronisé. À la prochaine frontière de pattern Renoise : Renoise commence à enregistrer ET le loop TD-3 démarre. Clic Stop pour terminer la prise.",
                notifier = function()
                  if start_recording() then launch_preview(true) end
                end },
    vb:checkbox { value = PREFS.loop.value,
                  notifier = function(v) PREFS.loop.value = v end },
    vb:text { text = "loop" },
    vb:checkbox { value = PREFS.sync_bpm.value,
                  notifier = function(v) PREFS.sync_bpm.value = v end },
    vb:text { text = "sync BPM" },
    vb:text { text = "  step =" },
    vb:popup {
      items = (function() local t = {} for _, r in ipairs(STEP_RATES) do table.insert(t, r.label) end return t end)(),
      value = PREFS.step_rate_index.value,
      notifier = function(v) PREFS.step_rate_index.value = v end,
      width = 90,
    },
    vb:button { text = "Stop", width = 50,
                notifier = function() stop_recording(); preview_stop() end,
                tooltip = "Arrête le Preview TD-3 et le Sample Recorder Renoise s'il tourne." },
    vb:button { text = "Panic", width = 60,
                notifier = function()
                  local out = get_midi_out(PREFS.midi_out_name.value)
                  if out then all_notes_off(out) end
                end },
    vb:button { text = "⚠  Write to TD-3", width = 140,
                notifier = function()
                  local out = get_midi_out(PREFS.midi_out_name.value)
                  if not out then renoise.app():show_warning("Aucun port MIDI valide.") return end
                  local slot = string.format("%s / %s",
                    td3.GROUP_LABELS[PREFS.group_index.value],
                    td3.format_pattern_label(PREFS.pattern_index.value - 1))
                  if renoise.app():show_prompt("Écrire le pattern ?",
                       "Va écraser le slot " .. slot .. " du TD-3. Continuer ?",
                       { "Écrire", "Annuler" }) == "Écrire" then
                    send_sysex(out, state.sysex)
                    renoise.app():show_status("Pattern envoyé vers " .. slot .. ".")
                  end
                end },
  }

  -- Assemble ----------------------------------------------------------------
  -- Barre de transpose : décalage demi-tons / octaves sur tout le pattern
  local toolbar_transpose = vb:row {
    vb:text { text = "Transpose", width = 70 },
    vb:button { text = "−12", width = 44, tooltip = "−1 octave",
                notifier = function() transpose_all(-12) end },
    vb:button { text = "−1",  width = 40, tooltip = "−1 demi-ton",
                notifier = function() transpose_all(-1) end },
    vb:button { text = "+1",  width = 40, tooltip = "+1 demi-ton",
                notifier = function() transpose_all(1) end },
    vb:button { text = "+12", width = 44, tooltip = "+1 octave",
                notifier = function() transpose_all(12) end },
  }

  -- Utilitaire intégré : import/export local .syx/.seq/.yml, équivalent Lua
  -- du CLI td3 — l'outil Renoise est autonome (aucune dépendance Python).
  local toolbar_load = vb:row {
    vb:text { text = "Charger", width = 90 },
    vb:button { text = ".syx", width = 70,
                tooltip = "Charge un dump SysEx .syx (F0…F7, opcode 0x78).",
                notifier = load_pattern_file },
    vb:button { text = ".seq", width = 70,
                tooltip = "Charge un export Synthtribe .seq (magic 23 98 54 76).",
                notifier = load_seq_file },
    vb:button { text = ".yml", width = 70,
                tooltip = "Charge un pattern au format YAML du CLI td3.",
                notifier = load_yaml_file },
  }
  local toolbar_save = vb:row {
    vb:text { text = "Enregistrer", width = 90 },
    vb:button { text = ".syx", width = 70,
                tooltip = "Exporte le pattern courant en SysEx .syx.",
                notifier = save_pattern_file },
    vb:button { text = ".seq", width = 70,
                tooltip = "Exporte en .seq (envoyable ensuite via `td3 send-seq`).",
                notifier = save_seq_file },
    vb:button { text = ".yml", width = 70,
                tooltip = "Exporte au format YAML lisible du CLI td3.",
                notifier = save_yaml_file },
  }

  local content_items = { toolbar1, toolbar2, toolbar_cfg, toolbar_cutoff, toolbar3, toolbar_transpose, toolbar_load, toolbar_save, vb:space { height = 6 } }
  for _, r in ipairs(oct_rows)   do table.insert(content_items, r) end
  table.insert(content_items, vb:space { height = 4 })
  for _, r in ipairs(pitch_rows) do table.insert(content_items, r) end
  table.insert(content_items, vb:space { height = 4 })
  table.insert(content_items, slide_row)
  table.insert(content_items, accent_row)
  table.insert(content_items, vb:space { height = 6 })
  table.insert(content_items, hex_view)
  table.insert(content_items, status_view)

  local content_def = { margin = 8, spacing = 2 }
  for i, c in ipairs(content_items) do content_def[i] = c end
  local content = vb:column(content_def)

  repaint_all(); rebuild_sysex_view()
  if _dialog and _dialog.visible then _dialog:close() end
  _dialog = renoise.app():show_custom_dialog("TD-3 Pattern Editor", content)
end

-- ===========================================================================
-- MIDI-live : éditeur séparé. La TD-3 n'est qu'un module de son ; aucune
-- écriture mémoire SysEx. Jusqu'à MAX_STEPS pas + FX par pas. Renoise
-- n'ayant pas d'onglets natifs, c'est un dialogue distinct (UI dédiée,
-- zéro risque de régression sur l'éditeur Hardware).
-- ===========================================================================

local COLOR_SEL = {0x30, 0x60, 0x90}   -- bleu : pas sélectionné (FX)
local COLOR_FX  = {0x40, 0x70, 0x40}   -- vert : pas porteur de FX
local COLOR_DIM = {0x6E, 0x6A, 0x60}   -- pas hors longueur active

local function new_live_steps()
  local t = {}
  for i = 1, MAX_STEPS do
    t[i] = { oct = 0, semi = 0, accent = false, slide = false,
             ratchet = FX_DEFAULT.ratchet, cutoff = FX_DEFAULT.cutoff,
             delay = FX_DEFAULT.delay, gate = FX_DEFAULT.gate }
  end
  return t
end

local function step_has_fx(s)
  return s.ratchet ~= FX_DEFAULT.ratchet or s.cutoff ~= FX_DEFAULT.cutoff
      or s.delay ~= FX_DEFAULT.delay or s.gate ~= FX_DEFAULT.gate
end

local function live_steps_to_string(steps)
  local parts = {}
  for i = 1, MAX_STEPS do
    local s = steps[i]
    parts[i] = string.format("%d:%d:%d:%d:%d:%d:%d:%d",
      s.oct, s.semi, s.accent and 1 or 0, s.slide and 1 or 0,
      s.ratchet, s.cutoff, s.delay, s.gate)
  end
  return table.concat(parts, ";")
end

local function live_steps_from_string(str)
  local steps = new_live_steps()
  if not str or str == "" then return steps end
  local i = 1
  for chunk in string.gmatch(str, "[^;]+") do
    -- Tolérant : 4 champs (ancien format hardware) ou 8 (FX). Les champs
    -- absents reprennent les valeurs FX neutres.
    local f = {}
    for v in string.gmatch(chunk, "[^:]+") do f[#f + 1] = tonumber(v) end
    if f[1] and i <= MAX_STEPS then
      steps[i] = {
        oct = f[1], semi = f[2] or 0,
        accent = (f[3] or 0) == 1, slide = (f[4] or 0) == 1,
        ratchet = f[5] or FX_DEFAULT.ratchet,
        cutoff  = f[6] or FX_DEFAULT.cutoff,
        delay   = f[7] or FX_DEFAULT.delay,
        gate    = f[8] or FX_DEFAULT.gate,
      }
    end
    i = i + 1
  end
  return steps
end

-- Fine-clock preview ---------------------------------------------------------
-- Un seul timer haute résolution + file d'évènements datés (ms). Permet
-- d'honorer delay (décalage intra-pas), ratchet (re-déclenchements),
-- gate (note-off anticipé) et cutoff (CC74) uniformément, et un arrêt
-- propre (on vide la file). Le legato/slide reprend la logique pile de
-- notes actives de l'éditeur Hardware.

local LP_TICK = 5  -- ms

local _lp_timer, _lp = nil, nil

local function lp_release_all()
  if not _lp then return end
  for _, n in ipairs(_lp.active) do
    send_short(_lp.out, 0x80, n, 0x40)
  end
  _lp.active = {}
end

local function lp_stop()
  if _lp_timer and renoise.tool():has_timer(_lp_timer) then
    renoise.tool():remove_timer(_lp_timer)
  end
  _lp_timer = nil
  if _lp then
    lp_release_all()
    send_short(_lp.out, 0xB0, 123, 0)
    send_short(_lp.out, 0xB0, 120, 0)
  end
  _lp = nil
end

local function lp_schedule(at, fn)
  local e = _lp.events
  _lp.seq = _lp.seq + 1
  e[#e + 1] = { at = at, seq = _lp.seq, fn = fn }
end

-- Programme tous les évènements MIDI du pas `idx` (1-based) débutant à
-- l'instant absolu `start` (ms).
local function lp_emit_step(idx, start)
  local s = _lp.steps[idx]
  local D = _lp.D
  if s.semi == 0 then
    lp_schedule(start, lp_release_all)            -- rest : gate fermé
    return
  end
  if s.cutoff >= 0 then
    local cc = s.cutoff
    lp_schedule(start, function() send_cc(_lp.out, 0x4A, cc) end)
  end
  local oct  = s.oct > 0 and s.oct or 2
  local midi = (oct + 1) * 12 + (s.semi - 1)
  local vel  = s.accent and _lp.vel_a or _lp.vel_n
  local base = start + (s.delay or 0)
  local R    = s.ratchet or 1

  if R <= 1 then
    lp_schedule(base, function()
      if s.slide and #_lp.active > 0 then
        local last = _lp.active[#_lp.active]
        if midi ~= last then              -- slide legato vers nouvelle pitch
          send_short(_lp.out, 0x90, midi, vel)
          table.insert(_lp.active, midi)
        end                               -- même pitch → sustain (rien)
      else
        lp_release_all()                  -- attaque propre
        send_short(_lp.out, 0x90, midi, vel)
        table.insert(_lp.active, midi)
      end
    end)
    if s.gate < 100 and not s.slide then  -- staccato : note-off anticipé
      lp_schedule(base + D * s.gate / 100,
        function() send_short(_lp.out, 0x80, midi, 0x40) end)
    end
  else                                    -- ratchet : re-déclenchements
    local sub = D / R
    lp_schedule(start, lp_release_all)
    for k = 0, R - 1 do
      local tk = base + k * sub
      if k > 0 then
        lp_schedule(tk - 2,
          function() send_short(_lp.out, 0x80, midi, 0x40) end)
      end
      local final = (k == R - 1)
      lp_schedule(tk, function()
        send_short(_lp.out, 0x90, midi, vel)
        if final then table.insert(_lp.active, midi) end
      end)
    end
    if s.gate < 100 then
      lp_schedule(base + (R - 1) * sub + sub * s.gate / 100,
        function() send_short(_lp.out, 0x80, midi, 0x40) end)
    end
  end
end

local function lp_start(steps, length, D, vel_n, vel_a, loop, out)
  lp_stop()
  _lp = { steps = steps, length = length, D = D, vel_n = vel_n,
          vel_a = vel_a, loop = loop, out = out, active = {},
          events = {}, seq = 0, t = 0, idx = 0, next_at = 0 }
  _lp_timer = function()
    local st = _lp
    if not st then return end
    st.t = st.t + LP_TICK
    -- Franchissement de frontière(s) de pas → on émet le pas suivant.
    while not st.ended and st.t >= st.next_at do
      if st.idx >= st.length then
        if st.loop then
          st.idx = 0
        else
          lp_schedule(st.next_at, function() lp_release_all() end)
          lp_schedule(st.next_at + 1, function() lp_stop() end)
          st.ended = true
          break
        end
      end
      lp_emit_step(st.idx + 1, st.next_at)
      st.idx = st.idx + 1
      st.next_at = st.next_at + st.D
    end
    -- Exécution des évènements échus (ordre stable at, puis seq).
    local due, keep = {}, {}
    for _, e in ipairs(st.events) do
      if e.at <= st.t then due[#due + 1] = e else keep[#keep + 1] = e end
    end
    table.sort(due, function(a, b)
      if a.at == b.at then return a.seq < b.seq end
      return a.at < b.at
    end)
    st.events = keep
    for _, e in ipairs(due) do e.fn() end
  end
  renoise.tool():add_timer(_lp_timer, LP_TICK)
end

-- Export vers une piste Renoise : écrit `length` lignes (note, volume =
-- accent, effet glide 0Gxx pour le slide, colonne delay pour le
-- microtiming, commande retrig pour le ratchet) dans la piste/pattern
-- courants. Au-delà : édition native Renoise (zéro duplication).
local function lp_export_to_track(steps, length)
  local ok, err = pcall(function()
    local song    = renoise.song()
    local pattern = song:pattern(song.selected_pattern_index)
    local track   = pattern:track(song.selected_track_index)
    local seqtrk  = song:track(song.selected_track_index)
    if seqtrk.type ~= renoise.Track.TRACK_TYPE_SEQUENCER then
      error("Sélectionnez une piste séquenceur (pas Master/Send).")
    end
    seqtrk.visible_effect_columns =
      math.max(1, seqtrk.visible_effect_columns)
    seqtrk.volume_column_visible = true
    seqtrk.delay_column_visible  = true
    for i = 1, length do
      local s    = steps[i]
      local line = track:line(i)
      local nc   = line:note_column(1)
      local ec   = line:effect_column(1)
      nc:clear(); ec:clear()
      if s.semi == 0 then
        nc.note_string = "OFF"
      else
        local oct  = s.oct > 0 and s.oct or 2
        local midi = (oct + 1) * 12 + (s.semi - 1)
        nc.note_value   = midi - 12          -- Renoise : note_value = MIDI-12
        nc.volume_value = s.accent and 0x7F or 0x60
        if (s.delay or 0) ~= 0 then
          -- delay column : 0..255 sur la durée d'une ligne. On mappe
          -- grossièrement ±60 ms → fraction de ligne (indicatif).
          local frac = math.max(-1, math.min(1, s.delay / 60))
          nc.delay_value = math.floor((frac % 1) * 255 + 0.5) % 256
        end
        if s.slide then
          ec.number_string = "0G"; ec.amount_value = 0x0F  -- glide
        elseif (s.ratchet or 1) > 1 then
          ec.number_string = "0R"; ec.amount_value = s.ratchet  -- retrig
        end
      end
    end
  end)
  if not ok then
    renoise.app():show_warning("Export piste impossible : " .. tostring(err))
  else
    renoise.app():show_status(string.format(
      "Pattern exporté sur la piste courante (%d lignes). Édition fine = Renoise natif.",
      length))
  end
end

local _live_dialog = nil

local function show_live_dialog()
  local vb    = renoise.ViewBuilder()
  local state = { steps = live_steps_from_string(PREFS.live_pattern_state.value),
                  length = PREFS.live_length.value, sel = 1 }
  local cells = { oct = {}, pitch = {}, accent = {}, slide = {}, fx = {} }
  local status_view
  local fx_boxes = {}

  local function persist()
    PREFS.live_pattern_state.value = live_steps_to_string(state.steps)
  end

  local function paint(view, color) view.color = color end

  local function cell_off_color(i)
    return (i > state.length) and COLOR_DIM or COLOR_OFF
  end

  local function repaint_step(i)
    local s = state.steps[i]
    local off = cell_off_color(i)
    for o = 1, 4  do paint(cells.oct[o][i],  s.oct == o  and COLOR_ON or off) end
    for p = 1, 12 do paint(cells.pitch[p][i], s.semi == p and COLOR_ON or off) end
    paint(cells.accent[i], s.accent and COLOR_ON or off)
    paint(cells.slide[i],  s.slide  and COLOR_ON or off)
    local fxc = off
    if step_has_fx(s) then fxc = COLOR_FX end
    if i == state.sel then fxc = COLOR_SEL end
    paint(cells.fx[i], fxc)
  end

  local function repaint_all()
    for i = 1, MAX_STEPS do repaint_step(i) end
  end

  local function status()
    status_view.text = string.format(
      "MIDI-live — %d pas — pas sélectionné %d   |   (aucune écriture mémoire TD-3)",
      state.length, state.sel)
  end

  local function sync_fx_boxes()
    local s = state.steps[state.sel]
    fx_boxes.ratchet.value = s.ratchet
    fx_boxes.cutoff.value  = s.cutoff
    fx_boxes.delay.value   = s.delay
    fx_boxes.gate.value    = s.gate
    fx_boxes.pas.value     = state.sel
  end

  local function on_change() persist(); status() end

  local function select_step(i)
    state.sel = math.max(1, math.min(MAX_STEPS, i))
    sync_fx_boxes(); repaint_all(); status()
  end

  -- Click handlers : note grid (OCT 1..4 → C1..C4 ; le pitch n'est pas
  -- bridé hors range comme en Hardware puisqu'on ne stocke pas sur la TD-3).
  local function toggle_oct(step, o)
    local s = state.steps[step]
    s.oct = (s.oct == o) and 0 or o
    repaint_step(step); on_change()
  end
  local function toggle_pitch(step, p)
    local s = state.steps[step]
    s.semi = (s.semi == p) and 0 or p
    repaint_step(step); on_change()
  end
  local function toggle_accent(step)
    state.steps[step].accent = not state.steps[step].accent
    repaint_step(step); on_change()
  end
  local function toggle_slide(step)
    state.steps[step].slide = not state.steps[step].slide
    repaint_step(step); on_change()
  end

  local function make_cell(fn)
    return vb:button { width = CELL_W, height = CELL_H,
                       color = COLOR_OFF, notifier = fn }
  end
  local function note_row(label, store, factory)
    local items = { vb:text { text = label, width = LABEL_W, font = "mono" } }
    for s = 1, MAX_STEPS do
      local btn = make_cell(factory(s))
      store[s] = btn
      table.insert(items, btn)
      if s % 4 == 0 and s < MAX_STEPS then
        table.insert(items, vb:space { width = 4 })
      end
    end
    return vb:row(items)
  end

  local oct_rows = {}
  for o = 4, 1, -1 do
    cells.oct[o] = {}
    local items = { vb:text { text = "OCT " .. o, width = LABEL_W, font = "mono" } }
    for s = 1, MAX_STEPS do
      local cell = make_cell(function() toggle_oct(s, o) end)
      cells.oct[o][s] = cell
      table.insert(items, cell)
      if s % 4 == 0 and s < MAX_STEPS then
        table.insert(items, vb:space { width = 4 })
      end
    end
    table.insert(oct_rows, vb:row(items))
  end
  local pitch_rows = {}
  for p = 12, 1, -1 do
    cells.pitch[p] = {}
    local items = { vb:text { text = PITCH_NAMES[p], width = LABEL_W, font = "mono" } }
    for s = 1, MAX_STEPS do
      local cell = make_cell(function() toggle_pitch(s, p) end)
      cells.pitch[p][s] = cell
      table.insert(items, cell)
      if s % 4 == 0 and s < MAX_STEPS then
        table.insert(items, vb:space { width = 4 })
      end
    end
    table.insert(pitch_rows, vb:row(items))
  end
  local slide_row  = note_row("SLIDE",  cells.slide,
    function(s) return function() toggle_slide(s) end end)
  local accent_row = note_row("ACCENT", cells.accent,
    function(s) return function() toggle_accent(s) end end)
  local fx_row     = note_row("FX·sel", cells.fx,
    function(s) return function() select_step(s) end end)

  -- Toolbars -----------------------------------------------------------------
  local midi_outs = renoise.Midi.available_output_devices()
  if #midi_outs == 0 then midi_outs = {"(no MIDI output detected)"} end
  local function find_index(t, v)
    for i, x in ipairs(t) do if x == v then return i end end
    return 1
  end

  local toolbar_io = vb:row {
    vb:text { text = "MIDI out", width = 60 },
    vb:popup { items = midi_outs,
               value = find_index(midi_outs, PREFS.midi_out_name.value),
               notifier = function(v) PREFS.midi_out_name.value = midi_outs[v] end,
               width = 180 },
    vb:text { text = "  Ch" },
    vb:valuebox { min = 1, max = 16, value = PREFS.midi_channel.value,
                  notifier = function(v) PREFS.midi_channel.value = v end },
    vb:text { text = "  Long." },
    vb:popup { items = { "16 pas", "32 pas" },
               value = (state.length == 32) and 2 or 1,
               notifier = function(v)
                 state.length = (v == 2) and 32 or 16
                 PREFS.live_length.value = state.length
                 if state.sel > state.length then select_step(state.length) end
                 repaint_all(); status()
               end,
               width = 80 },
    vb:text { text = "  Vel/acc" },
    vb:valuebox { min = 1, max = 127, value = PREFS.live_normal_velocity.value,
                  notifier = function(v) PREFS.live_normal_velocity.value = v end },
    vb:valuebox { min = 1, max = 127, value = PREFS.live_accent_velocity.value,
                  notifier = function(v) PREFS.live_accent_velocity.value = v end },
  }

  fx_boxes.pas = vb:valuebox { min = 1, max = MAX_STEPS, value = 1,
    notifier = function(v) select_step(v) end }
  fx_boxes.ratchet = vb:valuebox { min = 1, max = 8, value = 1,
    notifier = function(v) state.steps[state.sel].ratchet = v
      repaint_step(state.sel); on_change() end }
  fx_boxes.cutoff = vb:valuebox { min = -1, max = 127, value = -1,
    notifier = function(v) state.steps[state.sel].cutoff = v
      repaint_step(state.sel); on_change() end }
  fx_boxes.delay = vb:valuebox { min = -60, max = 60, value = 0,
    notifier = function(v) state.steps[state.sel].delay = v
      repaint_step(state.sel); on_change() end }
  fx_boxes.gate = vb:valuebox { min = 5, max = 100, value = 100,
    notifier = function(v) state.steps[state.sel].gate = v
      repaint_step(state.sel); on_change() end }

  local toolbar_fx = vb:row {
    vb:text { text = "Pas", width = 30 }, fx_boxes.pas,
    vb:text { text = "  Ratchet" }, fx_boxes.ratchet,
    vb:text { text = "  Cutoff(-1=off)" }, fx_boxes.cutoff,
    vb:text { text = "  Delay ms" }, fx_boxes.delay,
    vb:text { text = "  Gate %" }, fx_boxes.gate,
    vb:button { text = "→ tous les pas", width = 110,
      tooltip = "Applique les 4 FX du pas sélectionné à tous les pas.",
      notifier = function()
        local src = state.steps[state.sel]
        for i = 1, MAX_STEPS do
          local d = state.steps[i]
          d.ratchet, d.cutoff, d.delay, d.gate =
            src.ratchet, src.cutoff, src.delay, src.gate
        end
        repaint_all(); on_change()
      end },
    vb:button { text = "reset pas", width = 80,
      notifier = function()
        local s = state.steps[state.sel]
        s.ratchet, s.cutoff, s.delay, s.gate = FX_DEFAULT.ratchet,
          FX_DEFAULT.cutoff, FX_DEFAULT.delay, FX_DEFAULT.gate
        sync_fx_boxes(); repaint_step(state.sel); on_change()
      end },
  }

  local function compute_D()
    if PREFS.live_sync_bpm.value then
      local rate = STEP_RATES[PREFS.live_step_rate_index.value] or STEP_RATES[3]
      return math.floor((15000 / renoise.song().transport.bpm) / rate.mult + 0.5)
    end
    return PREFS.live_step_ms.value
  end

  local function go_preview()
    local out = get_midi_out(PREFS.midi_out_name.value)
    if not out then renoise.app():show_warning("Aucun port MIDI valide.") return end
    lp_start(state.steps, state.length, compute_D(),
             PREFS.live_normal_velocity.value,
             PREFS.live_accent_velocity.value,
             PREFS.live_loop.value, out)
    renoise.app():show_status("MIDI-live preview en cours…")
  end

  local toolbar_play = vb:row {
    vb:button { text = "▶ Preview", width = 90, notifier = go_preview },
    vb:button { text = "■ Stop", width = 70, notifier = lp_stop },
    vb:checkbox { value = PREFS.live_loop.value,
                  notifier = function(v) PREFS.live_loop.value = v end },
    vb:text { text = "loop" },
    vb:checkbox { value = PREFS.live_sync_bpm.value,
                  notifier = function(v) PREFS.live_sync_bpm.value = v end },
    vb:text { text = "sync BPM" },
    vb:text { text = "  step =" },
    vb:popup {
      items = (function() local t = {} for _, r in ipairs(STEP_RATES) do
                 table.insert(t, r.label) end return t end)(),
      value = PREFS.live_step_rate_index.value,
      notifier = function(v) PREFS.live_step_rate_index.value = v end,
      width = 90 },
    vb:text { text = "  step ms" },
    vb:valuebox { min = 20, max = 1000, value = PREFS.live_step_ms.value,
                  notifier = function(v) PREFS.live_step_ms.value = v end },
    vb:button { text = "Clear", width = 60,
      notifier = function() state.steps = new_live_steps()
        select_step(1); repaint_all(); on_change() end },
    vb:button { text = "Panic", width = 60,
      notifier = function()
        local out = get_midi_out(PREFS.midi_out_name.value)
        if out then for n = 0, 127 do send_short(out, 0x80, n, 0x40) end end
      end },
    vb:button { text = "→ Piste Renoise", width = 130,
      tooltip = "Écrit le pattern (notes + accent + slide + delay + ratchet) dans la piste/pattern Renoise courants pour édition native au-delà des limites TD-3.",
      notifier = function() lp_export_to_track(state.steps, state.length) end },
  }

  status_view = vb:text { text = "" }

  local items = { toolbar_io, toolbar_play, toolbar_fx, vb:space { height = 6 } }
  for _, r in ipairs(oct_rows)   do table.insert(items, r) end
  table.insert(items, vb:space { height = 4 })
  for _, r in ipairs(pitch_rows) do table.insert(items, r) end
  table.insert(items, vb:space { height = 4 })
  table.insert(items, slide_row)
  table.insert(items, accent_row)
  table.insert(items, vb:space { height = 4 })
  table.insert(items, fx_row)
  table.insert(items, vb:space { height = 6 })
  table.insert(items, status_view)

  local cdef = { margin = 8, spacing = 2 }
  for i, c in ipairs(items) do cdef[i] = c end

  sync_fx_boxes(); repaint_all(); status()
  if _live_dialog and _live_dialog.visible then _live_dialog:close() end
  _live_dialog = renoise.app():show_custom_dialog(
    "TD-3 MIDI-live (32 pas + FX)", vb:column(cdef))
end

-- Menu / keybinding registration -------------------------------------------

renoise.tool():add_menu_entry {
  name   = "Main Menu:Tools:TD-3 Pattern Editor...",
  invoke = show_dialog,
}
renoise.tool():add_menu_entry {
  name   = "Main Menu:Tools:TD-3 MIDI-live (32 pas + FX)...",
  invoke = show_live_dialog,
}
renoise.tool():add_menu_entry {
  name   = "Pattern Editor:TD-3 MIDI-live (32 pas + FX)...",
  invoke = show_live_dialog,
}
renoise.tool():add_keybinding {
  name   = "Global:Tools:TD-3 MIDI-live",
  invoke = show_live_dialog,
}
renoise.tool():add_menu_entry {
  name   = "Pattern Editor:TD-3 Pattern Editor...",
  invoke = show_dialog,
}
renoise.tool():add_keybinding {
  name   = "Global:Tools:TD-3 Pattern Editor",
  invoke = show_dialog,
}
