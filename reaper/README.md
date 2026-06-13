# Plugin Reaper — `td3_sysex_send.jsfx`

JSFX de contrôle de la **Behringer TD-3-MO** depuis Reaper. Il fait quatre
choses, toutes pilotées par SysEx/MIDI **référencés sur le dépôt** :

1. **Configurer** la TD-3 par SysEx : clock source (USB/DIN/Interne/Trig),
   rythme PPQ (1 PPS / 2 / 24 / 48), seuil d'accent, canal MIDI.
2. **Vérifier** ce que la TD-3 a *réellement* compris : on lui demande sa
   config (`0x75`) + son firmware (`0x08`) et on **affiche** la réponse
   (`0x76`/`0x09`) décodée, avec diagnostic ✓/!! — parce que les boutons
   de façade sont pénibles et qu'on veut une preuve de l'état.
3. **Lire une banque** depuis la TD-3 (`0x77`→`0x78`) et la **jouer en
   MIDI** (preview façon Renoise : slide = legato, accent = vélocité).
4. **Déclencher le séquenceur interne** : MIDI Start `0xFA` + horloge `0xF8`
   au PPQ choisi, Stop `0xFC`.

> Pourquoi pas de chargement de fichier `.sqs` sur disque ? Parce que la
> lecture d'octets bruts d'un binaire en JSFX **n'est pas documentée** par
> Reaper (`reaper.fm/sdk/js/file.php` ne précise pas l'unité lue par
> `file_var`/`file_mem`). Pour rester 100 % référençable, la banque est lue
> **depuis la TD-3 elle-même** (`0x77`/`0x78`), ce qui est entièrement
> documenté (`src/td3/sysex.py`).

## 1. Installation

Copier `td3_sysex_send.jsfx` dans le dossier des effets JS de Reaper :

- Reaper → **Options → Show REAPER resource path** → dossier `Effects/`.
- Y déposer le `.jsfx` (par ex. `Effects/td3/td3_sysex_send.jsfx`).
- Sur une piste : **FX → Add → JS: td3_sysex_send**.

## 2. Routing MIDI (c'est ICI qu'on choisit le device « TD-3-MO »)

Un JSFX **ne peut pas** énumérer les périphériques MIDI (limite du format) :
le choix du device se fait dans le routing de la piste.

1. **Sortie** : sur la piste, **Route → MIDI Hardware Output → `TD-3-MO`**
   (le port de sortie). C'est par là que partent les SysEx + notes.
2. **Entrée** : régler l'**Input de la piste sur `TD-3-MO`** (le port
   d'entrée), **Record-arm** + **Monitoring ON**. Indispensable pour que
   les réponses SysEx de la TD-3 (`0x76`/`0x09`/`0x78`) reviennent au JSFX
   via `midirecv_buf`. Sans ça, la case « Verifier » restera vide.
3. **Preferences → MIDI** : **ne pas** activer l'envoi de MIDI clock de
   Reaper vers `TD-3-MO` (le JSFX génère lui-même `0xF8` pour le
   séquenceur interne ; double horloge = comportement erratique — même
   avertissement que le README Renoise).
4. Sur la TD-3 : passer la clock source en **MIDI USB** (façade : FUNCTION
   + BACK&WRITE/NEXT + Selector 3 ; cf. `docs/td3-mo-fr.md`) — ou le faire
   directement avec le slider « Clock source » du plugin.

## 3. Workflow

1. Régler **Clock source = MIDI USB**, **Clock rate = 24 PPQ**, le **canal**,
   puis **`>>> Envoyer la config`**.
2. **`>>> Verifier`** : l'écran affiche le firmware + la config relue. Vérifier
   `Clock source : MIDI USB` et le canal (diagnostic ✓/!!).
3. **`>>> Lire la banque`** : le plugin demande les 64 patterns ; le compteur
   « Banque lue : N / 64 » monte.
4. Choisir **Pattern à jouer** (`0`=I-1A … `63`=IV-8B), régler vélocités et
   l'horloge (sync tempo Reaper ou ms manuel), puis **`>>> Play banque en
   MIDI`**. La TD-3 joue comme module de son. **`>>> Stop preview`** pour
   couper (envoie All-Notes-Off, **jamais** `0xFC` — qui figerait la TD-3
   en clock USB).
5. Alternative « vrai son 303 par le séquenceur interne » : **`>>> Start
   sequenceur interne`** (envoie `0xFA` + `0xF8`). Le pattern *sélectionné
   sur la façade* joue (la sélection de slot n'a aucun opcode SysEx, cf.
   limites du README principal). **`>>> Stop sequenceur interne`** = `0xFC`.

## 4. Références (chaque comportement est traçable)

| Sujet | Source |
|---|---|
| Header `F0 00 20 32 00 01 0A`, opcodes 0x77/0x78 | `src/td3/sysex.py` |
| Config 0x0E/0x1A/0x1B/0x1C, réponse 0x76, fw 0x08/0x09 | `src/td3/config.py` |
| Bloc 112 octets (nibbles, mask rest, step_count) | `src/td3/pattern.py` |
| `storage_to_midi = (raw & 0x7F) + 12` | `src/td3/notes.py` |
| Preview legato slide + vélocité accent, all-notes-off | `renoise/com.timox.td3-renoise.xrnx/main.lua` |
| Start/Clock/Stop temps réel (F8/FA/FC), PPQ | `docs/td3-mo-fr.md` |
| `midisend` / `midisend_buf` / `midirecv_buf` | reaper.fm/sdk/js/midi.php |
| `samplesblock` / `srate` / `tempo`, sliders, sections | reaper.fm/sdk/js/js.php |
| `gfx_*` (affichage) | reaper.fm/sdk/js/gfx.php |
| `sprintf` / `strcpy` / `%s` | reaper.fm/sdk/js/strings.php |

## 5. Test

La logique de protocole du JSFX (trames SysEx + décodage 0x78) est un port
exact de `src/td3`. Le test `tests/test_reaper_jsfx.py` rejoue cette
arithmétique en Python et la **confronte à la lib de référence** (trames
identiques à `td3.config`/`td3.sysex`, décodage identique à
`Pattern.from_bytes`). Lancer :

```bash
python -m pytest tests/test_reaper_jsfx.py -q
```
