--[[
TD-3 pattern codec (Lua port of the Python td3 lib).

Builds the 112-byte pattern data block and wraps it in a Behringer SysEx
F0 00 20 32 00 01 0A 78 <group> <pat> <unknown1:2> <data[2..111]> F7.

Pitch encoding: storage = MIDI − 12, clamped to 0x0C..0x30 (C1..C4).
Hold mask is INVERTED (1 = normal, 0 = tied to previous step).
Rest and Hold masks use the low-nibble layout 7654/3210/FEDC/BA98.
]]

local M = {}

M.STEPS         = 16
M.DATA_SIZE     = 112
M.DEFAULT_PITCH = 0x18           -- MIDI 36 = C2
M.PITCH_MIN     = 0x0C           -- MIDI 24 = C1
M.PITCH_MAX     = 0x30           -- MIDI 60 = C4

M.SYSEX_HEADER  = {0x00, 0x20, 0x32, 0x00, 0x01, 0x0A}
M.OP_WRITE      = 0x78

local b = bit                    -- LuaJIT bit library

local MASK_LAYOUT = {
  {8, 7, 6, 5},                  -- byte 0 nibble MSB→LSB → 1-based steps 8,7,6,5
  {4, 3, 2, 1},                  -- byte 1 → steps 4,3,2,1
  {16, 15, 14, 13},              -- byte 2 → steps 16,15,14,13
  {12, 11, 10, 9},               -- byte 3 → steps 12,11,10,9
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function clamp_pitch(storage)
  if storage < M.PITCH_MIN then return M.PITCH_MIN end
  if storage > M.PITCH_MAX then return M.PITCH_MAX end
  return storage
end

function M.midi_to_storage(midi)
  return clamp_pitch(midi - 12)
end

function M.storage_to_midi(storage)
  return b.band(storage, 0x7F) + 12
end

local NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
function M.midi_to_name(midi)
  local oct = math.floor(midi / 12) - 1
  return NOTE_NAMES[(midi % 12) + 1] .. tostring(oct)
end

-- Encode an array of integers as MSB/LSB nibble pairs.
local function encode_pairs(values)
  local out = {}
  for _, v in ipairs(values) do
    table.insert(out, b.band(b.rshift(v, 4), 0x0F))
    table.insert(out, b.band(v, 0x0F))
  end
  return out
end

-- Encode a 16-bool array (1-based, steps 1..16) into 4 mask bytes.
local function encode_step_mask(bits)
  local out = {0, 0, 0, 0}
  for byte_i, steps in ipairs(MASK_LAYOUT) do
    local nib = 0
    for bit_i, step in ipairs(steps) do
      if bits[step] then
        nib = b.bor(nib, b.rshift(0x08, bit_i - 1))
      end
    end
    out[byte_i] = nib
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Pattern encoding
-- ---------------------------------------------------------------------------

--- Build the 112-byte pattern data block.
-- @param steps  array of 16 step tables { pitch=int, accent=bool, slide=bool,
--               rest=bool, tie=bool }; missing fields default sensibly.
-- @param triplet     bool
-- @param step_count  1..16
-- @return table of 112 bytes (1-based)
function M.encode_data(steps, triplet, step_count)
  -- Triplet quirk : avec step_count=16 + triplet=true, le firmware TD-3
  -- casse les slides et avale les attaques. Synthtribe contourne ça en
  -- clampant step_count à 15. On fait pareil — MAIS contrairement à
  -- Synthtribe on ne touche pas au contenu du step 16 (pitch/accent/slide
  -- préservés). Le firmware ignorera step 16 en lecture puisque
  -- step_count=15, et un Read ultérieur retourne le pattern intact.
  if triplet and step_count > 15 then
    step_count = 15
  end

  local pitches, accent, slide = {}, {}, {}
  local rest_bits, hold_bits = {}, {}
  for i = 1, M.STEPS do
    local s = steps[i] or {}
    pitches[i] = clamp_pitch(s.pitch or M.DEFAULT_PITCH)
    accent[i]  = s.accent and 1 or 0
    slide[i]   = s.slide  and 1 or 0
    rest_bits[i] = s.rest and true or false
    hold_bits[i] = not (s.tie and true or false)
  end

  local data = {}
  for i = 1, M.DATA_SIZE do data[i] = 0 end

  -- 0x02..0x21: 32 bytes pitches
  local pp = encode_pairs(pitches)
  for i = 1, 32 do data[0x02 + i] = pp[i] end
  -- 0x22..0x41: accent
  local ap = encode_pairs(accent)
  for i = 1, 32 do data[0x22 + i] = ap[i] end
  -- 0x42..0x61: slide
  local sp = encode_pairs(slide)
  for i = 1, 32 do data[0x42 + i] = sp[i] end
  -- 0x62..0x63: triplet (LSB nibble = 1 if triplet)
  data[0x63] = 0
  data[0x64] = triplet and 1 or 0
  -- 0x64..0x65: step count
  data[0x65] = b.band(b.rshift(step_count, 4), 0x0F)
  data[0x66] = b.band(step_count, 0x0F)
  -- 0x66..0x67 (Lua 0x67..0x68): unknown2 already 0
  -- 0x68..0x6B (Lua 0x69..0x6C): hold mask
  local hb = encode_step_mask(hold_bits)
  for i = 1, 4 do data[0x68 + i] = hb[i] end
  -- 0x6C..0x6F (Lua 0x6D..0x70): rest mask
  local rb = encode_step_mask(rest_bits)
  for i = 1, 4 do data[0x6C + i] = rb[i] end

  return data
end

--- Wrap a 112-byte data block into a complete SysEx F0..F7 message.
function M.to_sysex(group, pattern_number, data)
  assert(group >= 0 and group <= 3, "group must be 0..3")
  assert(pattern_number >= 0 and pattern_number <= 15, "pattern must be 0..15")
  assert(#data == M.DATA_SIZE, "data must be 112 bytes")
  local msg = {0xF0}
  for _, x in ipairs(M.SYSEX_HEADER) do table.insert(msg, x) end
  table.insert(msg, M.OP_WRITE)
  table.insert(msg, group)
  table.insert(msg, pattern_number)
  -- The SysEx payload places the unknown1 pair right after group/pattern,
  -- then the remaining 110 bytes of the stored data block.
  for i = 1, M.DATA_SIZE do table.insert(msg, data[i]) end
  table.insert(msg, 0xF7)
  return msg
end

function M.bytes_to_hex(arr)
  local t = {}
  for _, x in ipairs(arr) do table.insert(t, string.format("%02X", x)) end
  return table.concat(t, " ")
end

-- ---------------------------------------------------------------------------
-- Decoding incoming pattern data (TD-3 → host, opcode 0x78)
-- ---------------------------------------------------------------------------

local function decode_pairs(data, first, count)
  local out = {}
  for i = 0, count - 1 do
    local hi = b.band(data[first + 2 * i],     0x0F)
    local lo = b.band(data[first + 2 * i + 1], 0x0F)
    out[i + 1] = b.bor(b.lshift(hi, 4), lo)
  end
  return out
end

local function decode_mask(data, first)
  local bits = {}
  for i = 1, M.STEPS do bits[i] = false end
  for byte_i, steps in ipairs(MASK_LAYOUT) do
    local nib = b.band(data[first + byte_i - 1], 0x0F)
    for bit_i, step in ipairs(steps) do
      if b.band(nib, b.rshift(0x08, bit_i - 1)) ~= 0 then
        bits[step] = true
      end
    end
  end
  return bits
end

--- Decode a 112-byte data block back to a structured representation.
-- Returns { pitches=[16], accent=[16], slide=[16], triplet=bool,
--           step_count=int, hold_mask=[16], rest_mask=[16] }.
-- Indexing is step-indexed (mirroring the encode side).
function M.decode_data(data)
  assert(#data == M.DATA_SIZE, "data must be 112 bytes")
  local pitches = decode_pairs(data, 0x02 + 1, 16)
  local accent  = decode_pairs(data, 0x22 + 1, 16)
  local slide   = decode_pairs(data, 0x42 + 1, 16)
  -- data[X + 1] reads byte at offset X (1-based array).
  local triplet = b.band(data[0x62 + 1] or 0, 0x0F) ~= 0
                  or b.band(data[0x63 + 1] or 0, 0x0F) ~= 0
  local sc_hi   = b.band(data[0x64 + 1] or 0, 0x0F)
  local sc_lo   = b.band(data[0x65 + 1] or 0, 0x0F)
  local step_count = b.lshift(sc_hi, 4) + sc_lo
  if step_count == 0 then step_count = 16 end
  local hold_mask = decode_mask(data, 0x68 + 1)
  local rest_mask = decode_mask(data, 0x6C + 1)
  return {
    pitches = pitches, accent = accent, slide = slide,
    triplet = triplet, step_count = step_count,
    hold_mask = hold_mask, rest_mask = rest_mask,
  }
end

--- Extract the 112-byte data block from a SysEx 0x78 response.
-- @param msg  1-indexed Lua array of bytes (full SysEx F0..F7).
-- @return     group (0..3), pattern_number (0..15), 112-byte data array
function M.parse_sysex_pattern(msg)
  if not msg or #msg < 1 + 6 + 1 + 2 + M.DATA_SIZE + 1 then
    return nil, "truncated SysEx"
  end
  if msg[1] ~= 0xF0 or msg[#msg] ~= 0xF7 then return nil, "missing F0/F7" end
  for i, v in ipairs(M.SYSEX_HEADER) do
    if msg[1 + i] ~= v then return nil, "wrong manufacturer header" end
  end
  if msg[8] ~= M.OP_WRITE then return nil, "not a pattern dump (opcode != 0x78)" end
  local group, pat = msg[9], msg[10]
  local data = {}
  for i = 1, M.DATA_SIZE do data[i] = msg[10 + i] end
  return group, pat, data
end

-- ---------------------------------------------------------------------------
-- Group / pattern label helpers (TB-303 convention)
-- ---------------------------------------------------------------------------

M.GROUP_LABELS = {"I", "II", "III", "IV"}

function M.format_pattern_label(num)
  local half = num < 8 and "A" or "B"
  return tostring((num % 8) + 1) .. half
end

-- ---------------------------------------------------------------------------
-- .seq container (single-pattern Synthtribe export) — Lua port of sqs.read_seq
--   magic 23 98 54 76, UTF-16BE product, UTF-16BE version,
--   uint32 size (=112), 112-byte data block. Slot lives in the filename only.
-- ---------------------------------------------------------------------------

M.SEQ_MAGIC = {0x23, 0x98, 0x54, 0x76}

local function rd_u32(bytes, off)            -- off is 1-based
  return (bytes[off] or 0) * 16777216 + (bytes[off + 1] or 0) * 65536
       + (bytes[off + 2] or 0) * 256 + (bytes[off + 3] or 0)
end

local function wr_u32(out, v)
  out[#out + 1] = math.floor(v / 16777216) % 256
  out[#out + 1] = math.floor(v / 65536) % 256
  out[#out + 1] = math.floor(v / 256) % 256
  out[#out + 1] = v % 256
end

local function wr_utf16be_string(out, s)
  local enc = {}
  for i = 1, #s do enc[#enc + 1] = 0; enc[#enc + 1] = s:byte(i) end
  wr_u32(out, #enc)
  for _, x in ipairs(enc) do out[#out + 1] = x end
end

--- Decode a .seq byte array → 112-byte data block (or nil, err).
function M.read_seq(bytes)
  if #bytes < 8 then return nil, "fichier trop court" end
  for i, v in ipairs(M.SEQ_MAGIC) do
    if bytes[i] ~= v then return nil, "magic .seq invalide" end
  end
  local off = 5
  for _ = 1, 2 do                            -- skip product + version strings
    local n = rd_u32(bytes, off)
    off = off + 4 + n
  end
  local size = rd_u32(bytes, off)
  off = off + 4
  if size ~= M.DATA_SIZE then
    return nil, "taille de bloc inattendue (" .. size .. ")"
  end
  local data = {}
  for i = 1, M.DATA_SIZE do data[i] = bytes[off + i - 1] end
  if data[M.DATA_SIZE] == nil then return nil, "données .seq tronquées" end
  return data
end

--- Encode a 112-byte data block into a .seq byte array.
function M.write_seq(data, product, version)
  product = product or "TD-3-MO"
  version = version or "2.0.1"
  local out = {}
  for _, v in ipairs(M.SEQ_MAGIC) do out[#out + 1] = v end
  wr_utf16be_string(out, product)
  wr_utf16be_string(out, version)
  wr_u32(out, M.DATA_SIZE)
  for i = 1, M.DATA_SIZE do out[#out + 1] = data[i] end
  return out
end

-- ---------------------------------------------------------------------------
-- YAML pattern format (the `td3` CLI's human format) — minimal line parser.
-- Only the keys this tool needs are read; a general YAML parser is overkill.
--   group: I   pattern: 1A   triplet: true   step_count: 15
--   seq:
--   - C#2 accent slide        (flags libres : accent slide tie rest)
--   - -                       (rest sans pitch)
-- ---------------------------------------------------------------------------

local NOTE_TO_SEMI = {
  C = 1, ["C#"] = 2, D = 3, ["D#"] = 4, E = 5, F = 6,
  ["F#"] = 7, G = 8, ["G#"] = 9, A = 10, ["A#"] = 11, B = 12,
}

--- Parse the td3 YAML text → decoded-shaped table (same shape as decode_data),
-- directly consumable by the editor's apply_decoded_to_steps.
function M.parse_yaml_pattern(text)
  local triplet, in_seq, seq = false, false, {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    local s = line:gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if s ~= "" and s:sub(1, 1) ~= "#" then
      if in_seq and s:sub(1, 1) == "-" then
        seq[#seq + 1] = s:sub(2):gsub("^%s+", "")
      else
        in_seq = false
        local key, val = s:match("^([%w_]+)%s*:%s*(.*)$")
        if key == "triplet" then
          triplet = (val == "true")
        elseif key == "seq" then
          in_seq = true
        end
      end
    end
  end

  local pitches, accent, slide, rest_mask = {}, {}, {}, {}
  for i = 1, M.STEPS do
    pitches[i] = M.DEFAULT_PITCH; accent[i] = 0; slide[i] = 0
    rest_mask[i] = true
  end

  for i = 1, math.min(#seq, M.STEPS) do
    local toks = {}
    for w in seq[i]:gmatch("%S+") do toks[#toks + 1] = w end
    local first = toks[1]
    local rest, acc, sld = false, false, false
    local storage, idx = M.DEFAULT_PITCH, 1
    if first and first ~= "-" then
      local nm, oc = first:match("^([A-G]#?)(-?%d+)$")
      local semi = nm and NOTE_TO_SEMI[nm]
      if semi then
        storage = M.midi_to_storage((tonumber(oc) + 1) * 12 + (semi - 1))
        idx = 2
      end
    elseif first == "-" then
      rest, idx = true, 2
    else
      rest = true                            -- empty item → rest
    end
    for k = idx, #toks do
      local f = toks[k]
      if f == "accent" then acc = true
      elseif f == "slide" then sld = true
      elseif f == "rest" then rest = true end
      -- "tie" : ignoré (la grille n'a pas de notion de tie, cf. Read TD-3)
    end
    pitches[i]   = storage
    accent[i]    = acc and 1 or 0
    slide[i]     = sld and 1 or 0
    rest_mask[i] = rest
  end

  return {
    pitches = pitches, accent = accent, slide = slide,
    rest_mask = rest_mask, triplet = triplet,
    step_count = #seq, hold_mask = {},
  }
end

--- Serialise a decoded pattern back to td3 YAML text.
function M.pattern_to_yaml(group, pat, d)
  local lines = {
    "group: " .. (M.GROUP_LABELS[group + 1] or "I"),
    "pattern: " .. M.format_pattern_label(pat),
    "triplet: " .. (d.triplet and "true" or "false"),
    "step_count: " .. tostring(d.step_count or M.STEPS),
    "seq:",
  }
  for i = 1, M.STEPS do
    local toks = { M.midi_to_name(M.storage_to_midi(d.pitches[i])) }
    if d.rest_mask[i] then toks[#toks + 1] = "rest" end
    if (d.accent[i] or 0) ~= 0 then toks[#toks + 1] = "accent" end
    if (d.slide[i]  or 0) ~= 0 then toks[#toks + 1] = "slide"  end
    lines[#lines + 1] = "- " .. table.concat(toks, " ")
  end
  return table.concat(lines, "\n") .. "\n"
end

return M
