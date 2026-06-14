/*
 * Validates maxforlive/td3.js against the authoritative Python `td3` lib:
 *   - SysEx 0x78 (Write) byte-exact for a crafted pattern,
 *   - SysEx 0x77 (Request) byte-exact,
 *   - JS encode -> decode round-trip,
 *   - JS parseSysexPattern of the Python-built message.
 * Run: node maxforlive/test_td3.mjs   (needs python3 + the repo's td3 lib)
 */
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const TD3 = require("./td3.js");

let failures = 0;
function check(name, cond) {
  console.log((cond ? "ok   " : "FAIL ") + name);
  if (!cond) failures++;
}

// A deliberately varied pattern (group III, pattern 3 = "4A").
const GROUP = 2, PAT = 3, TRIPLET = false, STEPCOUNT = 16;
const steps = [];
for (let i = 0; i < 16; i++) {
  steps.push({
    pitch: TD3.midiToStorage(36 + ((i * 5) % 24)), // wander C2..
    accent: i % 3 === 0,
    slide: i % 4 === 1,
    rest: i % 5 === 2,
    tie: i % 7 === 3
  });
}

const data = TD3.encodeData(steps, TRIPLET, STEPCOUNT);
const sysex = TD3.toSysex(GROUP, PAT, data);
const request = TD3.requestPattern(GROUP, PAT);

// --- Python reference -------------------------------------------------------
const py = `
import sys, json
from td3.pattern import Pattern, Step
from td3.sysex import pattern_to_sysex, request_pattern
steps = []
for i in range(16):
    note = 36 + ((i * 5) % 24)
    steps.append(Step(note=note, accent=(i % 3 == 0), slide=(i % 4 == 1),
                       rest=(i % 5 == 2), tie=(i % 7 == 3)))
p = Pattern(group=${GROUP}, number=${PAT}, triplet=False, step_count=16, steps=steps)
print(json.dumps({
  "write": list(pattern_to_sysex(p)),
  "request": list(request_pattern(${GROUP}, ${PAT})),
}))
`;
const ref = JSON.parse(
  execFileSync("python3", ["-c", py], {
    cwd: new URL("../src", import.meta.url).pathname,
    encoding: "utf8"
  })
);

check("Write SysEx length matches", sysex.length === ref.write.length);
check("Write SysEx byte-exact vs Python lib",
  TD3.bytesToHex(sysex) === TD3.bytesToHex(ref.write));
check("Request SysEx byte-exact vs Python lib",
  TD3.bytesToHex(request) === TD3.bytesToHex(ref.request));
check("SysEx payload is 7-bit clean",
  sysex.slice(1, -1).every((b) => b <= 0x7F));

// --- Round-trip -------------------------------------------------------------
const parsed = TD3.parseSysexPattern(ref.write);
check("parseSysexPattern: no error", !parsed.error);
check("parseSysexPattern: group/pattern", parsed.group === GROUP && parsed.pattern === PAT);

const dec = TD3.decodeData(parsed.data);
let rtOk = dec.stepCount === STEPCOUNT && dec.triplet === TRIPLET;
for (let i = 0; i < 16; i++) {
  const want = steps[i];
  if (dec.pitches[i] !== TD3.midiToStorage(TD3.storageToMidi(want.pitch))) rtOk = false;
  if (!!(dec.accent[i] & 1) !== !!want.accent) rtOk = false;
  if (!!(dec.slide[i] & 1) !== !!want.slide) rtOk = false;
  if (!!dec.restMask[i + 1] !== !!want.rest) rtOk = false;
  if (!dec.holdMask[i + 1] !== !!want.tie) rtOk = false; // hold inverted
}
check("encode -> decode round-trip preserves all step fields", rtOk);

check("midiToName(36) == C2", TD3.midiToName(36) === "C2");
check("formatPatternLabel(3) == 4A", TD3.formatPatternLabel(3) === "4A");
check("formatPatternLabel(8) == 1B", TD3.formatPatternLabel(8) === "1B");

console.log(failures === 0 ? "\nALL PASS" : `\n${failures} FAILURE(S)`);
process.exit(failures === 0 ? 0 : 1);
