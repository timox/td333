/*
 * TD-3 Pattern Editor — Max for Live glue.
 * Lives in a [js td3_device.js] object. Holds the edited pattern, builds
 * the Write SysEx (via td3.js), parses incoming Read dumps, and drives
 * the UI back.
 *
 * Inlet 0  : UI control messages
 *   group <0..3>          slot group (I..IV)
 *   pattern <0..15>       slot pattern (1A..8B)
 *   triplet <0|1>
 *   stepcount <1..16>
 *   octave <-2..2>        octave shift applied on pitch input
 *   cell <step0..15> <row0..2> <0|1>   matrixctrl: row0=active row1=accent row2=slide
 *   pitches <16 ints>     multislider 0..36 -> storage 0x0C..0x30
 *   write                 emit Write SysEx (outlet 0) + hex (outlet 1)
 *   request               emit Read request SysEx (outlet 0)
 *   clear                 reset pattern to all-rest, repaint UI
 *   dump                  print current pattern hex to Max window
 * Inlet 1  : raw MIDI bytes from [midiin] (SysEx bytes F0..F7)
 *
 * Outlet 0 : byte list -> [midiout]   (SysEx to send)
 * Outlet 1 : "set <hex>" -> a comment/textedit (last SysEx in hex)
 * Outlet 2 : UI repaint messages after a Read (menus, matrix, sliders)
 * Outlet 3 : "set <status>" -> status comment
 */

autowatch = 1;
inlets = 2;
outlets = 4;

var TD3 = require("td3.js");        // Max resolves td3.js next to this file

var state = {
  group: 0,
  pattern: 0,
  triplet: false,
  stepCount: 16,
  octave: 0,
  steps: []                         // 16 x { pitch, accent, slide, rest, tie }
};

function newSteps() {
  var s = [];
  for (var i = 0; i < 16; i++) {
    s.push({ pitch: TD3.DEFAULT_PITCH, accent: false, slide: false,
             rest: true, tie: false });
  }
  return s;
}
state.steps = newSteps();

function status(msg) { outlet(3, "set", msg); }

// --- inlet 0 : UI control ---------------------------------------------------

function group(g)      { state.group = clamp(g, 0, 3); }
function pattern(p)    { state.pattern = clamp(p, 0, 15); }
function triplet(t)    { state.triplet = !!t; }
function stepcount(n)  { state.stepCount = clamp(n, 1, 16); }
function octave(o)     { state.octave = clamp(o, -2, 2); }

// matrixctrl cell: row 0 = active (note present), 1 = accent, 2 = slide
function cell(step, row, val) {
  var st = state.steps[step];
  if (!st) return;
  if (row === 0) st.rest = (val === 0);
  else if (row === 1) st.accent = (val !== 0);
  else if (row === 2) st.slide = (val !== 0);
}

// multislider list: 16 values 0..36 -> storage 0x0C..0x30, +octave shift
function pitches() {
  var a = arrayfromargs(arguments);
  for (var i = 0; i < 16 && i < a.length; i++) {
    var midi = 24 + Math.round(a[i]) + state.octave * 12; // C1 = MIDI 24
    state.steps[i].pitch = TD3.midiToStorage(midi);
  }
}

function write() {
  try {
    var data = TD3.encodeData(state.steps, state.triplet, state.stepCount);
    var msg = TD3.toSysex(state.group, state.pattern, data);
    outlet(0, msg);
    outlet(1, "set", TD3.bytesToHex(msg));
    status("Write " + slotLabel() + " sent (" + msg.length + " bytes)");
  } catch (e) {
    status("ERROR: " + e.message);
  }
}

function request() {
  var msg = TD3.requestPattern(state.group, state.pattern);
  outlet(0, msg);
  status("Read request " + slotLabel() + " sent — waiting...");
}

function clear() {
  state.steps = newSteps();
  repaintUI();
  status("Pattern cleared");
}

function dump() {
  var data = TD3.encodeData(state.steps, state.triplet, state.stepCount);
  post("TD-3 " + slotLabel() + ": " +
       TD3.bytesToHex(TD3.toSysex(state.group, state.pattern, data)) + "\n");
}

// --- inlet 1 : incoming SysEx bytes from [midiin] ---------------------------

var rx = [];
var inSysex = false;

function msg_int(b) {
  if (inlet !== 1) return;
  if (b === 0xF0) { rx = [0xF0]; inSysex = true; return; }
  if (!inSysex) return;
  rx.push(b);
  if (b === 0xF7) {
    inSysex = false;
    handleSysex(rx);
    rx = [];
  }
}
// [midiin] may also emit lists; accept them too
function list() { var a = arrayfromargs(arguments); for (var i = 0; i < a.length; i++) msg_int.call(this, a[i]); }

function handleSysex(msg) {
  var r = TD3.parseSysexPattern(msg);
  if (r.error) { status("RX ignored: " + r.error); return; }
  var d = TD3.decodeData(r.data);
  state.group = r.group;
  state.pattern = r.pattern;
  state.triplet = d.triplet;
  state.stepCount = d.stepCount;
  for (var i = 0; i < 16; i++) {
    state.steps[i] = {
      pitch: d.pitches[i],
      accent: !!(d.accent[i] & 1),
      slide: !!(d.slide[i] & 1),
      rest: !!d.restMask[i + 1],
      tie: !d.holdMask[i + 1]
    };
  }
  repaintUI();
  status("Read OK: " + slotLabel() +
         (d.triplet ? " (triplet)" : "") + " " + d.stepCount + " steps");
}

// --- UI repaint (outlet 2) --------------------------------------------------

function repaintUI() {
  outlet(2, "group", state.group);
  outlet(2, "pattern", state.pattern);
  outlet(2, "triplet", state.triplet ? 1 : 0);
  outlet(2, "stepcount", state.stepCount);
  // matrix: emit "matrix col row val" for each of 16 steps x 3 rows
  for (var i = 0; i < 16; i++) {
    var st = state.steps[i];
    outlet(2, "matrix", i, 0, st.rest ? 0 : 1);
    outlet(2, "matrix", i, 1, st.accent ? 1 : 0);
    outlet(2, "matrix", i, 2, st.slide ? 1 : 0);
  }
  // sliders: "sliders v0 v1 ... v15" (0..36, octave-compensated)
  var sl = ["sliders"];
  for (var k = 0; k < 16; k++) {
    var midi = TD3.storageToMidi(state.steps[k].pitch) - state.octave * 12;
    sl.push(clamp(midi - 24, 0, 36));
  }
  outlet(2, sl);
}

// --- helpers ----------------------------------------------------------------

function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }
function slotLabel() {
  return (TD3.GROUP_LABELS[state.group] || "?") + "-" +
         TD3.formatPatternLabel(state.pattern);
}

function bang() { repaintUI(); }
function loadbang() { repaintUI(); status("Ready"); }
