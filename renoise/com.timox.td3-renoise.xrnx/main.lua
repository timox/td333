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
local STEPS       = 16

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
  loop                 = false,
  sync_bpm             = true, -- override step_ms with Renoise BPM
  filter_cutoff        = 64,   -- CC 74 last value
  -- Pattern state is persisted as a flat string of 16 step records:
  --   "o:s:a:l" per step, joined by ";". o ∈ 0..4 (0=rest), s ∈ 0..12 (1..12
  --   for C..B), a/l ∈ 0/1.
  pattern_state        = "",
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

local function get_midi_in(name, sysex_cb)
  if _midi_in_name ~= name then
    if _midi_in then _midi_in:close() end
    _midi_in, _midi_in_name = nil, nil
  end
  if not _midi_in and name and name ~= "" then
    _midi_in = renoise.Midi.create_input_device(name, nil, sysex_cb)
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

local function preview_stop()
  if _preview_timer and renoise.tool():has_timer(_preview_timer) then
    renoise.tool():remove_timer(_preview_timer)
  end
  _preview_timer = nil
  if _preview_state and _preview_state.out and _preview_state.last_note then
    send_short(_preview_state.out, 0x80, _preview_state.last_note, 0x40)
  end
  _preview_state = nil
end

local function preview_start(get_step, step_ms, normal_vel, accent_vel, loop, out)
  preview_stop()
  _preview_state = { out = out, step = 0, last_note = nil,
                     get_step = get_step, loop = loop }
  _preview_timer = function()
    local st = _preview_state
    if not st then return end
    if st.step >= STEPS then
      if st.loop then
        st.step = 0  -- restart in place; never release between loops to
                     -- support patterns that chain a slide at the wrap
      else
        if st.last_note then
          send_short(st.out, 0x80, st.last_note, 0x40); st.last_note = nil
        end
        preview_stop(); return
      end
    end
    local s = st.get_step(st.step + 1)  -- live read each tick
    if s and not s.rest and s.pitch then
      local midi = td3.storage_to_midi(s.pitch)
      local vel  = s.accent and accent_vel or normal_vel
      if s.slide and st.last_note then
        -- Slide / legato : send the new Note ON WITHOUT releasing the
        -- previous one. The TD-3 in mono mode interprets the overlapping
        -- Note ON as a portamento glide and keeps the gate open.
        send_short(st.out, 0x90, midi, vel)
      else
        if st.last_note then
          send_short(st.out, 0x80, st.last_note, 0x40)
        end
        send_short(st.out, 0x90, midi, vel)
      end
      st.last_note = midi
    else
      -- Rest : explicitly release the running note.
      if st.last_note then
        send_short(st.out, 0x80, st.last_note, 0x40); st.last_note = nil
      end
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

  local function on_change()
    persist(); rebuild_sysex_view()
  end

  -- Click handlers
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
    vb:button { text = "Clear", width = 70,
                notifier = function() state.steps = new_steps(); repaint_all(); on_change() end },
    vb:button { text = "Import depuis Renoise", width = 170,
                notifier = function()
                  import_from_renoise(state.steps, 0x60, -1)
                  repaint_all(); on_change()
                end },
    vb:button { text = "Preview ▶", width = 90,
                notifier = function()
                  local out = get_midi_out(PREFS.midi_out_name.value)
                  if not out then renoise.app():show_warning("Aucun port MIDI valide.") return end
                  local step_ms = PREFS.preview_step_ms.value
                  if PREFS.sync_bpm.value then
                    -- 1/16 note duration in ms, from Renoise's current BPM.
                    step_ms = math.floor(15000 / renoise.song().transport.bpm + 0.5)
                  end
                  -- Closure : la boucle relit l'état courant à chaque step,
                  -- les modifs en grille sont prises en compte sans Stop.
                  local function read_step(i) return step_to_td3(state.steps[i]) end
                  preview_start(read_step, step_ms,
                                PREFS.normal_velocity.value,
                                PREFS.accent_velocity.value,
                                PREFS.loop.value, out)
                end },
    vb:checkbox { value = PREFS.loop.value,
                  notifier = function(v) PREFS.loop.value = v end },
    vb:text { text = "loop" },
    vb:checkbox { value = PREFS.sync_bpm.value,
                  notifier = function(v) PREFS.sync_bpm.value = v end },
    vb:text { text = "sync BPM" },
    vb:button { text = "Stop", width = 50, notifier = preview_stop },
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
  local content_items = { toolbar1, toolbar2, toolbar_cutoff, toolbar3, vb:space { height = 6 } }
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

-- Menu / keybinding registration -------------------------------------------

renoise.tool():add_menu_entry {
  name   = "Main Menu:Tools:TD-3 Pattern Editor...",
  invoke = show_dialog,
}
renoise.tool():add_menu_entry {
  name   = "Pattern Editor:TD-3 Pattern Editor...",
  invoke = show_dialog,
}
renoise.tool():add_keybinding {
  name   = "Global:Tools:TD-3 Pattern Editor",
  invoke = show_dialog,
}
