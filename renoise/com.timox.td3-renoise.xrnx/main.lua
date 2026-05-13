--[[
TD-3 Pattern Export – Renoise scripting tool.

Workflow :
  1. on lit la pattern courante sur la piste sélectionnée (16 lignes,
     12 en mode triplet) ;
  2. mapping : note column → pitch (clampée à C1..C4) ; volume column
     non vide → accent ; effet "0Gxx" (Glide) sur la même ligne → slide ;
     ligne sans note → rest ;
  3. la fenêtre montre un aperçu textuel et le SysEx en hex à envoyer ;
  4. on peut "Preview audio" (envoi des Note On/Off temps réel au TD-3
     sans toucher la mémoire) puis "Write to TD-3" (envoi du SysEx vers
     le slot sélectionné, qui écrit en mémoire).
]]

local td3 = require "td3"

-- Helper used in the dialog: find a value's 1-based index in an array, or nil.
local function find_index(t, v)
  for i, x in ipairs(t) do if x == v then return i end end
  return nil
end

local PREFS = renoise.Document.create("Td3RenoisePrefs") {
  midi_out_name        = "",
  group_index          = 1,    -- 1..4 → I..IV
  pattern_index        = 1,    -- 1..16 → 1A..8B
  triplet              = false,
  step_count           = 16,
  note_column          = 0,    -- 0 = auto (first non-empty), 1..12 = explicit
  accent_threshold     = 0x60, -- volume column ≥ this → accent
  accent_velocity      = 100,
  preview_step_ms      = 125,  -- 1/16 note at 120 BPM
}
renoise.tool().preferences = PREFS

-- ---------------------------------------------------------------------------
-- Reading the current Renoise pattern
-- ---------------------------------------------------------------------------

-- Pick the meaningful note column on a given line.
-- column_pref = 0 → first non-empty column; else use that 1-based index.
local function pick_note_column(line, column_pref)
  if column_pref >= 1 then
    return line.note_columns[column_pref]
  end
  for i = 1, #line.note_columns do
    local c = line.note_columns[i]
    if c and c.note_value < 121 then  -- 121 = empty in Renoise
      return c
    end
  end
  return line.note_columns[1]
end

local function read_current_pattern(step_count)
  local song = renoise.song()
  local pattern = song:pattern(song.selected_pattern_index)
  local track_idx = song.selected_track_index
  local track = pattern:track(track_idx)
  local steps = {}
  for i = 1, td3.STEPS do
    local s = { rest = true }
    if i <= step_count then
      local line = track:line(i)
      local note_col = pick_note_column(line, PREFS.note_column.value)
      if note_col and note_col.note_value < 120 then
        -- Renoise note_value 0..119 ↔ MIDI note - 12 ; TD-3 storage = MIDI - 12,
        -- so note_value goes straight into storage with the same clamping.
        local midi = note_col.note_value + 12
        s.pitch = td3.midi_to_storage(midi)
        s.rest = false
        local vv = note_col.volume_value
        if vv < 128 and vv >= PREFS.accent_threshold.value then
          s.accent = true
        end
        for ec = 1, #line.effect_columns do
          local fx = line.effect_columns[ec]
          if fx.number_string == "0G" or fx.number_string == "G0" then
            s.slide = true
          end
        end
      end
    end
    steps[i] = s
  end
  return steps
end

-- ---------------------------------------------------------------------------
-- MIDI output helpers
-- ---------------------------------------------------------------------------

local _midi_out = nil
local _midi_out_name = nil

local function get_midi_out(name)
  if _midi_out_name ~= name then
    if _midi_out then _midi_out:close() end
    _midi_out = nil
  end
  if not _midi_out and name and name ~= "" then
    _midi_out = renoise.Midi.create_output_device(name)
    _midi_out_name = name
  end
  return _midi_out
end

local function send_sysex(out, msg)
  -- Renoise's MidiOutputDevice API has slightly varied across versions
  -- — try the modern SysEx-aware method first, fall back to send() with the
  -- full F0..F7 frame, then to a payload-only send_sysex_message().
  if type(out.send_sysex) == "function" then
    out:send_sysex(msg)
  elseif pcall(function() out:send(msg) end) then
    return
  elseif type(out.send_sysex_message) == "function" then
    local payload = {}
    for i = 2, #msg - 1 do table.insert(payload, msg[i]) end
    out:send_sysex_message(payload)
  else
    error("MIDI output does not support SysEx in this Renoise version")
  end
end

local function send_short(out, status, d1, d2)
  out:send { status, d1, d2 }
end

-- ---------------------------------------------------------------------------
-- Preview: stream the pattern as live Note On/Off
-- ---------------------------------------------------------------------------

local preview_timer = nil
local preview_state = nil

local function preview_stop()
  if preview_timer then
    if renoise.tool():has_timer(preview_timer) then
      renoise.tool():remove_timer(preview_timer)
    end
    preview_timer = nil
  end
  if preview_state and preview_state.out and preview_state.last_note then
    send_short(preview_state.out, 0x80, preview_state.last_note, 0x40)
  end
  preview_state = nil
end

local function preview_start(steps, step_count, step_ms, accent_velocity, out)
  preview_stop()
  preview_state = { out = out, step = 0, steps = steps, count = step_count,
                    last_note = nil, last_off_due = nil }
  preview_timer = function()
    local st = preview_state
    if not st then return end
    -- Switch off the previously playing note if any.
    if st.last_note then
      send_short(st.out, 0x80, st.last_note, 0x40)
      st.last_note = nil
    end
    if st.step >= st.count then
      preview_stop()
      return
    end
    local s = st.steps[st.step + 1]
    if s and not s.rest and s.pitch then
      local midi = td3.storage_to_midi(s.pitch)
      local vel  = s.accent and accent_velocity or 80
      send_short(st.out, 0x90, midi, vel)
      st.last_note = midi
    end
    st.step = st.step + 1
  end
  renoise.tool():add_timer(preview_timer, step_ms)
end

-- ---------------------------------------------------------------------------
-- Build a step preview string for the dialog
-- ---------------------------------------------------------------------------

local function format_step(s)
  if s.rest then return "—" end
  local txt = td3.midi_to_name(td3.storage_to_midi(s.pitch))
  if s.accent then txt = txt .. " !" end
  if s.slide  then txt = txt .. " ~" end
  if s.tie    then txt = txt .. " ^" end
  return txt
end

local function format_preview(steps, step_count)
  local lines = {}
  for i = 1, step_count do
    table.insert(lines, string.format("%2d  %s", i, format_step(steps[i])))
  end
  return table.concat(lines, "\n")
end

local function chunk_hex(arr, per_line)
  per_line = per_line or 16
  local out, line = {}, {}
  for i, b in ipairs(arr) do
    table.insert(line, string.format("%02X", b))
    if i % per_line == 0 then
      table.insert(out, table.concat(line, " "))
      line = {}
    end
  end
  if #line > 0 then table.insert(out, table.concat(line, " ")) end
  return table.concat(out, "\n")
end

-- ---------------------------------------------------------------------------
-- Dialog
-- ---------------------------------------------------------------------------

local function group_items()  return td3.GROUP_LABELS end
local function pattern_items()
  local t = {}
  for n = 0, 15 do table.insert(t, td3.format_pattern_label(n)) end
  return t
end

local function show_dialog()
  local vb = renoise.ViewBuilder()
  local preview_view  = vb:multiline_text { width = 360, height = 220, font = "mono" }
  local hex_view      = vb:multiline_text { width = 360, height = 200, font = "mono" }
  local status_view   = vb:text { text = "" }

  local midi_outs = renoise.Midi.available_output_devices()
  if #midi_outs == 0 then midi_outs = {"(no MIDI output detected)"} end

  local state = { steps = nil, sysex = nil }

  local function refresh()
    local step_count = PREFS.step_count.value
    state.steps = read_current_pattern(step_count)
    local data = td3.encode_data(state.steps, PREFS.triplet.value, step_count)
    state.sysex = td3.to_sysex(
      PREFS.group_index.value - 1,
      PREFS.pattern_index.value - 1,
      data)
    preview_view.text = format_preview(state.steps, step_count)
    hex_view.text     = chunk_hex(state.sysex, 16)
    local slot = string.format("%s / %s",
      td3.GROUP_LABELS[PREFS.group_index.value],
      td3.format_pattern_label(PREFS.pattern_index.value - 1))
    status_view.text = "Slot cible : " .. slot
                       .. "  |  SysEx : " .. tostring(#state.sysex) .. " octets"
  end

  local content = vb:column {
    margin = 10, spacing = 8,
    vb:text { text = "Source : pattern + piste sélectionnées dans Renoise.",
              font = "italic" },
    vb:row {
      vb:text { text = "Step count", width = 80 },
      vb:valuebox { min = 1, max = 16, value = PREFS.step_count.value,
                    notifier = function(v) PREFS.step_count.value = v; refresh() end },
      vb:checkbox { value = PREFS.triplet.value,
                    notifier = function(v) PREFS.triplet.value = v; refresh() end },
      vb:text { text = "triplet" },
    },
    vb:row {
      vb:text { text = "TD-3 slot", width = 80 },
      vb:popup { items = group_items(), value = PREFS.group_index.value,
                 notifier = function(v) PREFS.group_index.value = v; refresh() end },
      vb:popup { items = pattern_items(), value = PREFS.pattern_index.value,
                 notifier = function(v) PREFS.pattern_index.value = v; refresh() end },
    },
    vb:row {
      vb:text { text = "Note column", width = 80 },
      vb:popup {
        items = { "Auto (1ère non vide)", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12" },
        value = PREFS.note_column.value + 1,
        notifier = function(v) PREFS.note_column.value = v - 1; refresh() end,
      },
    },
    vb:row {
      vb:text { text = "MIDI out", width = 80 },
      vb:popup { items = midi_outs,
                 value = math.max(1, find_index(midi_outs, PREFS.midi_out_name.value) or 1),
                 notifier = function(v) PREFS.midi_out_name.value = midi_outs[v] end },
    },
    vb:row {
      vb:text { text = "Accent ≥ vol", width = 80 },
      vb:valuebox { min = 1, max = 127, value = PREFS.accent_threshold.value,
                    notifier = function(v) PREFS.accent_threshold.value = v; refresh() end },
      vb:text { text = "  Preview vel." },
      vb:valuebox { min = 1, max = 127, value = PREFS.accent_velocity.value,
                    notifier = function(v) PREFS.accent_velocity.value = v end },
      vb:text { text = "  Step ms" },
      vb:valuebox { min = 20, max = 1000, value = PREFS.preview_step_ms.value,
                    notifier = function(v) PREFS.preview_step_ms.value = v end },
    },
    vb:text { text = "Aperçu steps :", font = "bold" },
    preview_view,
    vb:text { text = "SysEx :", font = "bold" },
    hex_view,
    status_view,
    vb:row {
      vb:button { text = "Rafraîchir depuis Renoise", width = 180,
                  notifier = refresh },
      vb:button { text = "Preview audio (Note On/Off)", width = 180,
        notifier = function()
          local out = get_midi_out(PREFS.midi_out_name.value)
          if not out then renoise.app():show_warning("Aucun port MIDI valide.") return end
          preview_start(state.steps, PREFS.step_count.value,
                        PREFS.preview_step_ms.value,
                        PREFS.accent_velocity.value, out)
        end },
    },
    vb:row {
      vb:button { text = "Stop preview", width = 180, notifier = preview_stop },
      vb:button { text = "⚠  Write to TD-3 (SysEx)", width = 180,
        notifier = function()
          local out = get_midi_out(PREFS.midi_out_name.value)
          if not out then renoise.app():show_warning("Aucun port MIDI valide.") return end
          local slot = string.format("%s / %s",
            td3.GROUP_LABELS[PREFS.group_index.value],
            td3.format_pattern_label(PREFS.pattern_index.value - 1))
          local ok = renoise.app():show_prompt("Écrire le pattern ?",
            "Va écraser le slot " .. slot .. " du TD-3. Continuer ?",
            { "Écrire", "Annuler" }) == "Écrire"
          if ok then
            send_sysex(out, state.sysex)
            renoise.app():show_status("Pattern envoyé vers " .. slot .. ".")
          end
        end },
    },
  }

  refresh()
  renoise.app():show_custom_dialog("TD-3 Pattern Export", content)
end

-- ---------------------------------------------------------------------------
-- Menu entries
-- ---------------------------------------------------------------------------

renoise.tool():add_menu_entry {
  name   = "Main Menu:Tools:TD-3 Pattern Export...",
  invoke = show_dialog,
}
renoise.tool():add_menu_entry {
  name   = "Pattern Editor:TD-3 Pattern Export...",
  invoke = show_dialog,
}
renoise.tool():add_keybinding {
  name   = "Global:Tools:TD-3 Pattern Export",
  invoke = show_dialog,
}
