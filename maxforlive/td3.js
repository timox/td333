/*
 * TD-3 pattern codec — JavaScript port of td3.lua (the Renoise Lua codec),
 * itself a port of the Python `td3` lib.
 *
 * Dual-use:
 *   - inside Max/MSP `[js td3.js]` (no module system, defines a global TD3),
 *   - in Node.js for testing (module.exports when available).
 *
 * SysEx layout:
 *   F0 00 20 32 00 01 0A 78 <group> <pat> <data[0..111]> F7
 * Pitch storage = MIDI - 12, clamped 0x0C..0x30 (C1..C4).
 * Hold mask is INVERTED (1 = normal, 0 = tied to previous step).
 * Rest/Hold masks use the low-nibble layout 7654/3210/FEDC/BA98.
 */

var TD3 = (function () {
  var M = {};

  M.STEPS         = 16;
  M.DATA_SIZE     = 112;
  M.DEFAULT_PITCH = 0x18;  // MIDI 36 = C2
  M.PITCH_MIN     = 0x0C;  // MIDI 24 = C1
  M.PITCH_MAX     = 0x30;  // MIDI 60 = C4

  M.SYSEX_HEADER  = [0x00, 0x20, 0x32, 0x00, 0x01, 0x0A];
  M.OP_REQUEST    = 0x77;
  M.OP_WRITE      = 0x78;

  // byte i -> 1-based steps it carries (MSB..LSB of the low nibble)
  var MASK_LAYOUT = [
    [8, 7, 6, 5],
    [4, 3, 2, 1],
    [16, 15, 14, 13],
    [12, 11, 10, 9]
  ];

  function clampPitch(s) {
    if (s < M.PITCH_MIN) return M.PITCH_MIN;
    if (s > M.PITCH_MAX) return M.PITCH_MAX;
    return s;
  }

  M.midiToStorage = function (midi) { return clampPitch(midi - 12); };
  M.storageToMidi = function (s) { return (s & 0x7F) + 12; };

  var NOTE_NAMES = ["C", "C#", "D", "D#", "E", "F", "F#",
                    "G", "G#", "A", "A#", "B"];
  M.midiToName = function (midi) {
    var oct = Math.floor(midi / 12) - 1;
    return NOTE_NAMES[midi % 12] + oct;
  };

  function encodePairs(values) {
    var out = [];
    for (var i = 0; i < values.length; i++) {
      out.push((values[i] >> 4) & 0x0F);
      out.push(values[i] & 0x0F);
    }
    return out;
  }

  function decodePairs(data, first, count) {
    var out = [];
    for (var i = 0; i < count; i++) {
      var hi = data[first + 2 * i] & 0x0F;
      var lo = data[first + 2 * i + 1] & 0x0F;
      out.push((hi << 4) | lo);
    }
    return out;
  }

  // bits: 1-based array (steps 1..16) of booleans -> 4 mask bytes
  function encodeStepMask(bits) {
    var out = [0, 0, 0, 0];
    for (var bi = 0; bi < MASK_LAYOUT.length; bi++) {
      var nib = 0;
      var steps = MASK_LAYOUT[bi];
      for (var k = 0; k < steps.length; k++) {
        if (bits[steps[k]]) nib |= (0x08 >> k);
      }
      out[bi] = nib;
    }
    return out;
  }

  function decodeStepMask(data, first) {
    var bits = [];
    for (var i = 1; i <= M.STEPS; i++) bits[i] = false;
    for (var bi = 0; bi < MASK_LAYOUT.length; bi++) {
      var nib = data[first + bi] & 0x0F;
      var steps = MASK_LAYOUT[bi];
      for (var k = 0; k < steps.length; k++) {
        if (nib & (0x08 >> k)) bits[steps[k]] = true;
      }
    }
    return bits;
  }

  /*
   * Build the 112-byte pattern data block.
   * steps: array (0-based, 16 entries) of { pitch, accent, slide, rest, tie }.
   * Returns a 112-element byte array (0-based).
   */
  M.encodeData = function (steps, triplet, stepCount) {
    // Triplet quirk: step_count 16 + triplet breaks slides/attacks on the
    // TD-3 firmware. Clamp to 15 (like Synthtribe) but keep step 16's data.
    if (triplet && stepCount > 15) stepCount = 15;

    var pitches = [], accent = [], slide = [];
    var restBits = [], holdBits = [];
    for (var i = 1; i <= M.STEPS; i++) {
      var s = steps[i - 1] || {};
      pitches[i]  = clampPitch(s.pitch != null ? s.pitch : M.DEFAULT_PITCH);
      accent[i]   = s.accent ? 1 : 0;
      slide[i]    = s.slide ? 1 : 0;
      restBits[i] = !!s.rest;
      holdBits[i] = !s.tie;            // inverted
    }

    var data = [];
    for (var j = 0; j < M.DATA_SIZE; j++) data[j] = 0;

    var seq1 = [], seq0 = [];          // re-pack 1-based -> 0-based for pairs
    for (var p = 1; p <= M.STEPS; p++) seq1.push(pitches[p]);
    for (var a = 1; a <= M.STEPS; a++) seq0.push(accent[a]);
    var sl = [];
    for (var q = 1; q <= M.STEPS; q++) sl.push(slide[q]);

    var pp = encodePairs(seq1);
    for (var x = 0; x < 32; x++) data[0x02 + x] = pp[x];
    var ap = encodePairs(seq0);
    for (var y = 0; y < 32; y++) data[0x22 + y] = ap[y];
    var sp = encodePairs(sl);
    for (var z = 0; z < 32; z++) data[0x42 + z] = sp[z];

    data[0x62] = 0;
    data[0x63] = triplet ? 1 : 0;
    data[0x64] = (stepCount >> 4) & 0x0F;
    data[0x65] = stepCount & 0x0F;
    // 0x66..0x67 unknown2 stay 0

    var hb = encodeStepMask(holdBits);
    for (var h = 0; h < 4; h++) data[0x68 + h] = hb[h];
    var rb = encodeStepMask(restBits);
    for (var r = 0; r < 4; r++) data[0x6C + r] = rb[r];

    return data;
  };

  M.toSysex = function (group, patternNumber, data) {
    if (group < 0 || group > 3) throw new Error("group must be 0..3");
    if (patternNumber < 0 || patternNumber > 15)
      throw new Error("pattern must be 0..15");
    if (data.length !== M.DATA_SIZE)
      throw new Error("data must be 112 bytes");
    var msg = [0xF0];
    for (var i = 0; i < M.SYSEX_HEADER.length; i++) msg.push(M.SYSEX_HEADER[i]);
    msg.push(M.OP_WRITE);
    msg.push(group);
    msg.push(patternNumber);
    for (var j = 0; j < M.DATA_SIZE; j++) msg.push(data[j]);
    msg.push(0xF7);
    return msg;
  };

  M.requestPattern = function (group, patternNumber) {
    var msg = [0xF0];
    for (var i = 0; i < M.SYSEX_HEADER.length; i++) msg.push(M.SYSEX_HEADER[i]);
    msg.push(M.OP_REQUEST, group, patternNumber, 0xF7);
    return msg;
  };

  M.bytesToHex = function (arr) {
    var t = [];
    for (var i = 0; i < arr.length; i++) {
      var h = (arr[i] & 0xFF).toString(16).toUpperCase();
      t.push(h.length < 2 ? "0" + h : h);
    }
    return t.join(" ");
  };

  /*
   * Decode a 112-byte block back to a structured form.
   * Returns { pitches[16], accent[16], slide[16], triplet, stepCount,
   *           holdMask{1..16}, restMask{1..16} } (pitch arrays 0-based).
   */
  M.decodeData = function (data) {
    if (data.length !== M.DATA_SIZE)
      throw new Error("data must be 112 bytes");
    var pitches = decodePairs(data, 0x02, 16);
    var accent  = decodePairs(data, 0x22, 16);
    var slide   = decodePairs(data, 0x42, 16);
    var triplet = ((data[0x62] || 0) & 0x0F) !== 0
               || ((data[0x63] || 0) & 0x0F) !== 0;
    var scHi = (data[0x64] || 0) & 0x0F;
    var scLo = (data[0x65] || 0) & 0x0F;
    var stepCount = (scHi << 4) + scLo;
    if (stepCount === 0) stepCount = 16;
    var holdMask = decodeStepMask(data, 0x68);
    var restMask = decodeStepMask(data, 0x6C);
    return {
      pitches: pitches, accent: accent, slide: slide,
      triplet: triplet, stepCount: stepCount,
      holdMask: holdMask, restMask: restMask
    };
  };

  /*
   * Extract group, pattern, and the 112-byte block from a full SysEx
   * 0x78 message (1D array F0..F7). Returns { group, pattern, data } or
   * { error }.
   */
  M.parseSysexPattern = function (msg) {
    if (!msg || msg.length < 1 + 6 + 1 + 2 + M.DATA_SIZE + 1)
      return { error: "truncated SysEx" };
    if (msg[0] !== 0xF0 || msg[msg.length - 1] !== 0xF7)
      return { error: "missing F0/F7" };
    for (var i = 0; i < M.SYSEX_HEADER.length; i++) {
      if (msg[1 + i] !== M.SYSEX_HEADER[i])
        return { error: "wrong manufacturer header" };
    }
    if (msg[7] !== M.OP_WRITE)
      return { error: "not a pattern dump (opcode != 0x78)" };
    var group = msg[8], pat = msg[9];
    var data = [];
    for (var j = 0; j < M.DATA_SIZE; j++) data[j] = msg[10 + j];
    return { group: group, pattern: pat, data: data };
  };

  M.GROUP_LABELS = ["I", "II", "III", "IV"];

  M.formatPatternLabel = function (num) {
    var half = num < 8 ? "A" : "B";
    return String((num % 8) + 1) + half;
  };

  return M;
})();

if (typeof module !== "undefined" && module.exports) {
  module.exports = TD3;
}
