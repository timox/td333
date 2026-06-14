/*
 * TD-3 live — Max for Live MIDI Effect glue.
 * Plays the Behringer TD-3 / TD-3-MO as a real-time sound module from
 * Live (no SysEx, no pattern storage). Translates incoming MIDI into
 * TB-303 semantics:
 *   - accent : velocity >= threshold  -> emit accentVel, else normalVel
 *   - slide  : monophonic last-note priority; overlapping (legato) input
 *              notes overlap on output so the TD-3 slides between them
 *   - cutoff : a control -> CC74 (the only sound-design CC Behringer exposes)
 *
 * Dual-use: runs in [js td3_live.js] (Max) and in Node (tests) — when
 * `outlet` is absent, emitted MIDI is pushed to TD3LIVE.sink instead.
 *
 * Inlet 0 (control + notes via [notein]->[pack]):
 *   note <pitch> <vel>     note on (vel>0) / note off (vel==0)
 *   channel <1..16>
 *   threshold <1..127>     accent velocity threshold
 *   normalvel <1..127>     output velocity for non-accent notes
 *   accentvel <1..127>     output velocity for accent notes
 *   slidems <0..50>        extra overlap (ms) added on legato for a
 *                          reliable slide on hardware
 *   cutoff <0..127>        -> CC74
 *   panic                  all notes off
 *
 * Outlet 0 : [status, d1, d2] raw MIDI -> [midiout]
 * Outlet 1 : "set <status>" -> status comment
 */

var TD3LIVE = { sink: null };          // Node test hook

var CFG = {
  channel: 1, threshold: 96,
  normalVel: 80, accentVel: 127,
  slideMs: 10
};

var held = [];                          // stack of pitches still physically held
var velOf = {};                         // pitch -> chosen output velocity
var sounding = null;                    // pitch currently gated on the TD-3

function _emit3(status, d1, d2) {
  var m = [status & 0xFF, d1 & 0x7F, d2 & 0x7F];
  if (typeof outlet !== "undefined") outlet(0, m);
  else if (TD3LIVE.sink) TD3LIVE.sink.push(m);
}
function _status(s) {
  if (typeof outlet !== "undefined") outlet(1, "set", s);
}
function clamp(v, lo, hi) { return v < lo ? lo : (v > hi ? hi : v); }

function noteOn(pitch, vel) {
  var ch = CFG.channel - 1;
  var ov = (vel >= CFG.threshold) ? CFG.accentVel : CFG.normalVel;
  velOf[pitch] = ov;

  if (sounding !== null && sounding !== pitch) {
    // Legato in the input == slide on the TD-3. Send the new note ON
    // FIRST so the gates overlap, then release the previous note (after
    // an optional few ms so hardware reliably registers the slide).
    var prev = sounding;
    _emit3(0x90 | ch, pitch, ov);
    if (CFG.slideMs > 0 && typeof Task !== "undefined") {
      var t = new Task(function () { _emit3(0x80 | ch, prev, 0); });
      t.schedule(CFG.slideMs);
    } else {
      _emit3(0x80 | ch, prev, 0);
    }
  } else {
    _emit3(0x90 | ch, pitch, ov);
  }

  // mono last-note stack
  for (var i = held.length - 1; i >= 0; i--) if (held[i] === pitch) held.splice(i, 1);
  held.push(pitch);
  sounding = pitch;
}

function noteOff(pitch) {
  var ch = CFG.channel - 1;
  for (var i = held.length - 1; i >= 0; i--) if (held[i] === pitch) held.splice(i, 1);
  delete velOf[pitch];

  if (pitch !== sounding) return;       // a non-gated held note was released

  if (held.length > 0) {
    // mono fallback: slide back to the most recent still-held note
    var nx = held[held.length - 1];
    _emit3(0x90 | ch, nx, velOf[nx] || CFG.normalVel);
    _emit3(0x80 | ch, pitch, 0);
    sounding = nx;
  } else {
    _emit3(0x80 | ch, pitch, 0);
    sounding = null;
  }
}

// --- message handlers (Max calls the function named after the message) ------

function note(pitch, vel) {
  if (vel > 0) noteOn(pitch | 0, vel | 0);
  else noteOff(pitch | 0);
}
function list(pitch, vel) { note(pitch, vel); }   // [pack pitch vel] -> list

function channel(n)   { CFG.channel  = clamp(n | 0, 1, 16); }
function threshold(n) { CFG.threshold = clamp(n | 0, 1, 127); }
function normalvel(n) { CFG.normalVel = clamp(n | 0, 1, 127); }
function accentvel(n) { CFG.accentVel = clamp(n | 0, 1, 127); }
function slidems(n)   { CFG.slideMs  = clamp(n | 0, 0, 50); }
function cutoff(v)    { _emit3(0xB0 | (CFG.channel - 1), 74, clamp(v | 0, 0, 127)); }

function panic() {
  var ch = CFG.channel - 1;
  _emit3(0xB0 | ch, 123, 0);            // All Notes Off
  for (var p = 0; p < 128; p++) _emit3(0x80 | ch, p, 0);
  held = []; velOf = {}; sounding = null;
  _status("panic — all notes off");
}

function loadbang() { _status("TD-3 live ready"); }

if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    CFG: CFG,
    note: note, channel: channel, threshold: threshold,
    normalvel: normalvel, accentvel: accentvel, slidems: slidems,
    cutoff: cutoff, panic: panic,
    _reset: function () { held = []; velOf = {}; sounding = null; },
    setSink: function (s) { TD3LIVE.sink = s; }
  };
}
