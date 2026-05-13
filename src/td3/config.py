"""TD-3 device configuration via SysEx — opcodes outside of pattern transfer.

Reverse-engineered from the 303patterns.com / AudioPump bundle. The device
exposes a comprehensive config block (MIDI channels, clock source, accent
threshold, etc.) addressable through 1-byte opcodes that follow the standard
Behringer manufacturer header :code:`F0 00 20 32 00 01 0A`.

Opcodes (TX = host → TD-3, RX = TD-3 → host):

    0x01 RX   generic ACK to SET commands     payload: [0, 0]
    0x03 TX   special control                 0x03 0x30 → enter DFU/firmware update mode
    0x04 TX   request model name              payload: []
    0x05 RX   model response                  payload: ASCII bytes
    0x06 TX   request product name            payload: []
    0x07 RX   product response                payload: ASCII bytes
    0x08 TX   request firmware version        payload: [0]
    0x09 RX   firmware version response       payload: [0, major, minor, revision]
    0x0E TX   set MIDI channels               payload: [1, out_ch-1, in_ch-1]
    0x0F TX   set MIDI input transpose        payload: [val + 12]
    0x11 TX   set pitch bend semitones        payload: [val, 0]
    0x12 TX   set key priority                payload: [val]   (0=Low,1=High,2=Last)
    0x14 TX   set multi-trigger               payload: [bool, 0]
    0x19 TX   set clock trigger polarity      payload: [val] (0=Fall,1=Rise)
    0x1A TX   set clock trigger rate          payload: [val] (0=1PPS,1=2PPQ,2=24,3=48)
    0x1B TX   set clock source                payload: [val] (0=Int,1=DIN,2=USB,3=Trig)
    0x1C TX   set accent velocity threshold   payload: [val] (0..127)
    0x50 TX   enter / exit hardware test mode payload: [0/1]
              In test mode the TD-3 sends channel-aftertouch (0xA0..0xA4)
              to report tempo knob / track knob / mode knob / front-panel
              button positions in real time.
    0x75 TX   request full config             payload: []
    0x76 RX   config dump response            payload: see Td3Config below
    0x77 TX   request pattern                 payload: [group, pattern]
    0x78 TX/RX pattern data                   payload: see td3.sysex
    0x7D TX   reset to factory defaults       payload: []

The config response (0x76) payload layout, in order::

    [0] midi_output_channel - 1     (0..15)
    [1] midi_input_channel - 1
    [2] midi_input_transpose + 12   (0..24 → semitones -12..+12)
    [3] pitch_bend_semitones        (0..12)
    [4] key_priority                (0=Low, 1=High, 2=Last)
    [5] multi_trigger               (0/1)
    [6] clock_trigger_polarity      (0=Fall, 1=Rise)
    [7] clock_trigger_rate          (0=1 PPS, 1=2 PPQ, 2=24 PPQ, 3=48 PPQ)
    [8] clock_source                (0=Internal, 1=MIDI DIN, 2=MIDI USB, 3=Trigger)
    [9] accent_velocity_threshold   (0..127, incoming velocity above this is accented)
"""
from __future__ import annotations

from dataclasses import dataclass

from .sysex import MFR_HEADER

# Opcodes
OP_REQUEST_FW    = 0x08
OP_FW_RESPONSE   = 0x09
OP_SET_CHANNELS  = 0x0E
OP_SET_TRANSPOSE = 0x0F
OP_SET_PB_RANGE  = 0x11
OP_SET_PRIORITY  = 0x12
OP_SET_MULTITRIG = 0x14
OP_SET_CLK_POL   = 0x19
OP_SET_CLK_RATE  = 0x1A
OP_SET_CLK_SRC   = 0x1B
OP_SET_ACC_THR   = 0x1C
OP_REQUEST_CFG   = 0x75
OP_CFG_RESPONSE  = 0x76
OP_RESET         = 0x7D
# Additional opcodes documented on 303patterns.com
OP_ACK           = 0x01
OP_DFU           = 0x03
OP_GET_MODEL     = 0x04
OP_MODEL_RESP    = 0x05
OP_GET_PRODUCT   = 0x06
OP_PRODUCT_RESP  = 0x07
OP_TEST_MODE     = 0x50


def _frame(opcode: int, *payload: int) -> bytes:
    return bytes([0xF0]) + MFR_HEADER + bytes([opcode, *payload, 0xF7])


# --------------------------------------------------------------------------
# Outgoing (host → TD-3)
# --------------------------------------------------------------------------

def request_firmware_version() -> bytes:
    return _frame(OP_REQUEST_FW, 0)


def request_config() -> bytes:
    return _frame(OP_REQUEST_CFG)


def reset_to_defaults() -> bytes:
    return _frame(OP_RESET)


def request_model() -> bytes:
    return _frame(OP_GET_MODEL)


def request_product_name() -> bytes:
    return _frame(OP_GET_PRODUCT)


def enter_test_mode(enabled: bool = True) -> bytes:
    """Toggle hardware test mode. In test mode the TD-3 emits channel
    aftertouch messages on channels 0..4 reflecting the position of the
    front-panel tempo / track / mode rotaries and button presses."""
    return _frame(OP_TEST_MODE, 1 if enabled else 0)


def enter_dfu_mode() -> bytes:
    """Reboot into firmware-update (DFU) mode. After this the TD-3 re-enumerates
    over USB as PID 1227 and will accept a .syx firmware blob from Synthtribe.
    Do not call casually."""
    return bytes([0xF0]) + MFR_HEADER + bytes([OP_DFU, 0x30, 0xF7])


def set_midi_channels(input_ch: int, output_ch: int) -> bytes:
    """Both 1..16; the wire format stores 0..15."""
    return _frame(OP_SET_CHANNELS, 1, _clip16(output_ch) - 1, _clip16(input_ch) - 1)


def set_midi_input_transpose(semitones: int) -> bytes:
    """semitones in -12..+12, wire format 0..24."""
    if not -12 <= semitones <= 12:
        raise ValueError("transpose must be -12..+12")
    return _frame(OP_SET_TRANSPOSE, semitones + 12)


def set_pitch_bend_range(semitones: int) -> bytes:
    if not 0 <= semitones <= 12:
        raise ValueError("pitch bend range must be 0..12")
    return _frame(OP_SET_PB_RANGE, semitones, 0)


def set_key_priority(value: int) -> bytes:
    """0 = Low, 1 = High, 2 = Last."""
    if value not in (0, 1, 2):
        raise ValueError("key priority must be 0..2")
    return _frame(OP_SET_PRIORITY, value)


def set_multi_trigger(enabled: bool) -> bytes:
    return _frame(OP_SET_MULTITRIG, 1 if enabled else 0, 0)


def set_clock_source(value: int) -> bytes:
    """0=Internal, 1=MIDI DIN, 2=MIDI USB, 3=Trigger."""
    if value not in (0, 1, 2, 3):
        raise ValueError("clock source must be 0..3")
    return _frame(OP_SET_CLK_SRC, value)


def set_clock_trigger_rate(value: int) -> bytes:
    """0=1 PPS, 1=2 PPQ, 2=24 PPQ, 3=48 PPQ."""
    if value not in (0, 1, 2, 3):
        raise ValueError("clock trigger rate must be 0..3")
    return _frame(OP_SET_CLK_RATE, value)


def set_clock_trigger_polarity(value: int) -> bytes:
    """0=Fall, 1=Rise."""
    if value not in (0, 1):
        raise ValueError("clock trigger polarity must be 0 or 1")
    return _frame(OP_SET_CLK_POL, value)


def set_accent_velocity_threshold(value: int) -> bytes:
    if not 0 <= value <= 127:
        raise ValueError("accent velocity threshold must be 0..127")
    return _frame(OP_SET_ACC_THR, value)


# --------------------------------------------------------------------------
# Incoming (TD-3 → host)
# --------------------------------------------------------------------------

@dataclass
class FirmwareVersion:
    major: int
    minor: int
    revision: int

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.revision}"


@dataclass
class ModelName:
    name: str


@dataclass
class ProductName:
    name: str


@dataclass
class AckReply:
    pass  # Generic acknowledgement of a SET command.


@dataclass
class Td3Config:
    midi_output_channel: int          # 1..16
    midi_input_channel: int           # 1..16
    midi_input_transpose: int         # -12..+12
    pitch_bend_semitones: int         # 0..12
    key_priority: int                 # 0=Low, 1=High, 2=Last
    multi_trigger: bool
    clock_trigger_polarity: int       # 0=Fall, 1=Rise
    clock_trigger_rate: int           # 0=1PPS, 1=2PPQ, 2=24PPQ, 3=48PPQ
    clock_source: int                 # 0=Int, 1=DIN, 2=USB, 3=Trig
    accent_velocity_threshold: int    # 0..127


def parse_sysex(msg: bytes):
    """Decode a Behringer-framed SysEx message into a typed object.

    Returns FirmwareVersion or Td3Config depending on the opcode, or None if
    the message is unrecognised.
    """
    if not msg or msg[0] != 0xF0 or msg[-1] != 0xF7:
        return None
    if msg[1:1 + len(MFR_HEADER)] != MFR_HEADER:
        return None
    body = msg[1 + len(MFR_HEADER):-1]
    if not body:
        return None
    opcode, *payload = body
    if opcode == OP_ACK:
        return AckReply()
    if opcode == OP_MODEL_RESP:
        return ModelName(name=bytes(payload).decode("ascii", errors="replace"))
    if opcode == OP_PRODUCT_RESP:
        return ProductName(name=bytes(payload).decode("ascii", errors="replace"))
    if opcode == OP_FW_RESPONSE and len(payload) >= 4:
        return FirmwareVersion(major=payload[1], minor=payload[2], revision=payload[3])
    if opcode == OP_CFG_RESPONSE and len(payload) >= 10:
        return Td3Config(
            midi_output_channel       = payload[0] + 1,
            midi_input_channel        = payload[1] + 1,
            midi_input_transpose      = payload[2] - 12,
            pitch_bend_semitones      = payload[3],
            key_priority              = payload[4],
            multi_trigger             = bool(payload[5]),
            clock_trigger_polarity    = payload[6],
            clock_trigger_rate        = payload[7],
            clock_source              = payload[8],
            accent_velocity_threshold = payload[9],
        )
    return None


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

def _clip16(v: int) -> int:
    if not 1 <= v <= 16:
        raise ValueError("MIDI channel must be 1..16")
    return v
