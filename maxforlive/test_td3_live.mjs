/*
 * Unit tests for the TD-3 live transform (maxforlive/td3_live.js), run in
 * Node by capturing emitted MIDI via the sink hook. No Max required.
 * Run: node maxforlive/test_td3_live.mjs
 */
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const L = require("./td3_live.js");

let failures = 0;
function check(name, cond, extra) {
  console.log((cond ? "ok   " : "FAIL ") + name + (cond ? "" : "  " + (extra || "")));
  if (!cond) failures++;
}
let sink = [];
L.setSink(sink);
function reset() { sink.length = 0; L._reset(); }

const NON = 144, OFF = 128, CC = 176; // 0x90/0x80/0xB0 on channel 1

// 1. accent threshold
reset(); L.threshold(96); L.normalvel(80); L.accentvel(127);
L.note(40, 60);
check("soft note -> normalVel", sink[0][0] === NON && sink[0][2] === 80, JSON.stringify(sink));
reset();
L.note(40, 110);
check("hard note -> accentVel", sink[0][0] === NON && sink[0][2] === 127, JSON.stringify(sink));

// 2. separate notes: no slide (off before next on)
reset();
L.note(40, 60); L.note(40, 0); L.note(43, 60);
check("staccato: A on, A off, B on (3 msgs)", sink.length === 3, JSON.stringify(sink));
check("staccato: A off before B on",
  sink[1][0] === OFF && sink[1][1] === 40 && sink[2][0] === NON && sink[2][1] === 43,
  JSON.stringify(sink));

// 3. legato == slide: new note ON emitted BEFORE previous note OFF
reset();
L.note(40, 60);        // A on
L.note(43, 60);        // B on while A still held -> slide
check("legato: B note-on precedes A note-off",
  sink[1][0] === NON && sink[1][1] === 43 && sink[2][0] === OFF && sink[2][1] === 40,
  JSON.stringify(sink));

// 4. mono fallback: release B while A still held -> slide back to A
reset();
L.note(40, 60); L.note(43, 60); L.note(43, 0);
const last2 = sink.slice(-2);
check("mono fallback: B off -> A re-gated (slide back)",
  last2[0][0] === NON && last2[0][1] === 40 && last2[1][0] === OFF && last2[1][1] === 43,
  JSON.stringify(sink));

// 5. channel routing
reset(); L.channel(10);
L.note(40, 60);
check("channel 10 -> status 0x90|9 (153)", sink[0][0] === (0x90 | 9), JSON.stringify(sink));
reset();
L.cutoff(64);
check("cutoff -> CC74 on ch10", sink[0][0] === (0xB0 | 9) && sink[0][1] === 74 && sink[0][2] === 64,
  JSON.stringify(sink));
L.channel(1);

// 6. panic
reset();
L.note(40, 60);
L.panic();
check("panic: emits All Notes Off (CC123)",
  sink.some((m) => m[0] === CC && m[1] === 123), JSON.stringify(sink.slice(0, 3)));

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILURE(S)`);
process.exit(failures === 0 ? 0 : 1);
