# td3 — CLI manuelle

Documentation détaillée de la commande `td3` (lib Python). Tous les exemples
sont copiables-collables et testés sur Windows + PowerShell.

## Installation

Depuis le dossier du repo cloné :

```powershell
# Lib seule (manipulation .sqs / .syx / YAML, pas de MIDI live)
pip install -e .

# Avec MIDI live (recommandé pour envoyer / monitorer)
pip install -e ".[midi]"
```

Si la commande `td3` n'apparaît pas dans le PATH, lancer à la place :

```powershell
python -m td3.cli <commande> <options>
```

## Lister les ports MIDI disponibles

```powershell
td3 ports
```

Sortie typique sur Windows (numéros de port variables) :

```
Input ports:
  oulaaa 0
  Default App Loopback (A) 5
  Default App Loopback (B) 6
  TD-3-MO 8
Output ports:
  Microsoft GS Wavetable Synth 0
  Default App Loopback (A) 6
  Default App Loopback (B) 7
  TD-3-MO 9
```

Le nom complet inclut un index numérique (`TD-3-MO 8`). Pour le passer à
une commande, vous pouvez utiliser un **fragment** : `"TD-3-MO"` suffit si
unique, sinon `"TD-3-MO 8"` exactement.

---

## Extraire les 64 patterns d'un .sqs vers YAML

```powershell
td3 unpack td3dump.sqs --out patterns
```

Crée 65 fichiers dans `patterns/` :
- `_meta.yml` : product code + version firmware
- `I-1A.yml`, `I-2A.yml`, ..., `I-8B.yml` (groupe I, 16 patterns)
- `II-1A.yml`, ..., `IV-8B.yml` (groupes II, III, IV)

Chaque fichier est un YAML lisible-éditable. Exemple `I-1A.yml` (pattern d'usine
"Best Served with Beat") :

```yaml
group: I
pattern: 1A
triplet: false
step_count: 16
seq:
- F#3 slide
- E3 slide
- D3 rest          # rest avec pitch fantôme D3 préservé
- B2 slide
- D3 slide
- G#2 slide rest
- D3 slide rest
- F#2 rest
- B3 slide
- C2
- '-'              # rest "vide", pitch placeholder par défaut
- '-'
- C2
- C2
- C2
- '-'
```

Notes :
- Une `seq` a toujours **16 entrées** (les rests utilisent `-` ou `<pitch> rest`)
- Les flags sont **accent**, **slide**, **tie**, **rest** dans n'importe quel ordre
- Les notes sont en MIDI standard (C4 = MIDI 60). TD-3 range : **C1..C4**.

## Recompiler des YAML vers un .sqs

```powershell
td3 pack patterns --out my_bank.sqs
```

Crée `my_bank.sqs` byte-identique à `td3dump.sqs` (si vous n'avez rien modifié).
Importable dans Synthtribe via leur bouton **Import**.

Options :
- `--product "TD-3-MO"` : produit dans le header (défaut)
- `--version "2.0.1"` : firmware string (défaut)

## Convertir un YAML en .syx

```powershell
td3 yaml-to-syx mon_pattern.yml
# → crée mon_pattern.syx (123 octets)

td3 yaml-to-syx mon_pattern.yml --out custom_name.syx
```

Le fichier .syx contient une trame SysEx complète `F0 00 20 32 00 01 0A 78 ...
F7`, importable dans n'importe quel logiciel SysEx compatible (MIDI-OX,
SysEx Librarian…) ou drag-droppé dans Synthtribe.

## Envoyer un pattern vers la TD-3 via MIDI

```powershell
td3 send mon_pattern.yml --port "TD-3-MO"
```

Sortie :

```
sent pattern IV-1A to 'TD-3-MO 8'
```

Le `group` et `pattern` du fichier YAML déterminent le slot cible. Pour
forcer un slot différent, modifier le YAML avant `send`. La TD-3 répond
par un ACK SysEx (`F0 00 20 32 00 01 0A 01 00 00 F7`) qui peut être
visualisé via `td3 monitor`.

Après le `send`, sur la TD-3 face avant :
1. MODE = PATTERN PLAY
2. TRACK/PATTERN GROUP = lettre correspondante (I, II, III ou IV)
3. ACCENT/PATTERN A (rangée du bas) ou SLIDE/PATTERN B
4. Selector 1..8 (les 8 premières touches du clavier 13 keys)
5. START → la TD-3 joue le pattern écrit

## Envoyer une banque entière

```powershell
td3 send-all patterns --port "TD-3-MO"
```

Itère sur tous les `*.yml` du dossier et envoie chaque pattern dans son
slot respectif (déduit du `group` + `pattern` du YAML). Utile pour
flasher une banque complète à partir d'un dossier de YAMLs édités.

## Décoder un .syx vers YAML

```powershell
td3 syx-to-yaml exporte_synthtribe.syx --out decoded.yml
```

Inverse de `yaml-to-syx`. Permet d'inspecter le contenu d'un .syx
hardware avec un format lisible.

Si le `.syx` contient **plusieurs** patterns concaténés (dump multi-slot),
la commande crée un dossier au lieu d'un fichier unique :

```powershell
td3 syx-to-yaml banque_complete.syx --out yaml_dir
# → yaml_dir/I-1A.yml, yaml_dir/I-2A.yml, ...
```

## Monitorer le trafic MIDI vers la TD-3

```powershell
td3 monitor --port "Loopback (A)" --forward-to "TD-3-MO"
```

Setup recommandé :
1. Synthtribe (ou un autre logiciel) → MIDI Out = "Default App Loopback (A)"
2. Notre `td3 monitor` écoute "Loopback (A)" et forwarde à la vraie TD-3
3. Tout ce qui passe est affiché en temps réel avec timestamps

Sortie typique :

```
Écoute sur : 'Default App Loopback (A) 5'   forward → 'TD-3-MO 9'
Ctrl-C pour arrêter.

[  0.123] sysex (11 octets) : F0 00 20 32 00 01 0A 77 03 00 F7
[  0.156] sysex (123 octets) : F0 00 20 32 00 01 0A 78 03 00 00 00 02 0A ...
[  0.245] note_on channel=0 note=60 velocity=80 time=0
```

Options :
- `--clock` : afficher aussi les MIDI Clock (filtrés par défaut, génère
  24 messages/quart de noir)
- `--forward-to` est optionnel (omettre = écoute pure sans relais)

## Sniff interactif (un contrôle à la fois)

```powershell
td3 sniff --port "TD-3-MO"
```

Pour chaque contrôle TD-3 listé (CUTOFF, RESONANCE, DECAY, etc.), invite
l'utilisateur à bouger le potard correspondant et capture le message
MIDI émis. Sortie JSON `td3_cc_map.json` avec le mapping découvert.

À noter : la TD-3 **n'émet généralement pas de MIDI** quand on tourne ses
potards (limite firmware Behringer). Cette commande est plus utile pour
écouter ce que Synthtribe envoie via un port loopMIDI / Loopback.

## Active probe CC

```powershell
td3 probe --port "TD-3-MO"
```

Pour chaque CC de 0 à 127, envoie une alternance 0/127 vers la TD-3 et
vous demande à l'oreille si vous entendez un effet. Permet de découvrir
quels CC le firmware reconnaît en input réellement (en pratique :
seul **CC 74 = Filter Cutoff** est documenté ; le reste est du test
empirique).

---

## Workflows pratiques

### Workflow 1 — Backup avant modif Synthtribe

Avant de toucher quoi que ce soit dans Synthtribe :

```powershell
# 1. Exporter le .sqs courant depuis Synthtribe (bouton Export)
# 2. Le décoder en YAML lisibles
td3 unpack export_synthtribe.sqs --out backup_2025-05-14

# 3. Modifier dans Synthtribe
# 4. Si on veut revenir à l'état d'avant :
td3 pack backup_2025-05-14 --out restore.sqs
# Importer restore.sqs dans Synthtribe
```

### Workflow 2 — Composer un pattern en YAML et l'envoyer

```yaml
# bass_intro.yml
group: I
pattern: 1A
triplet: false
step_count: 16
seq:
- C2 accent slide
- D2
- C2 accent slide
- D2
- '-'
- C2 slide
- E2 accent
- '-'
- C2 accent slide
- D2
- C2 accent slide
- D2
- '-'
- F2 slide
- E2 accent
- '-'
```

```powershell
td3 send bass_intro.yml --port "TD-3-MO"
```

Puis sur la TD-3 : MODE = PATTERN PLAY · GROUP = I · PATTERN A · Selector 1 · START.

### Workflow 3 — Itérer sur un pattern via .yml

```powershell
# 1. Composer dans l'éditeur graphique Renoise
# 2. Ou export depuis Synthtribe puis :
td3 syx-to-yaml mon_export.syx --out brouillon.yml

# 3. Éditer brouillon.yml dans un éditeur de texte
notepad brouillon.yml

# 4. Re-envoyer
td3 send brouillon.yml --port "TD-3-MO"
# → écraser le slot du fichier, vérifier à l'oreille, modifier, etc.
```

### Workflow 4 — Banque thématique complète

```powershell
mkdir bank_techno
# Créer un YAML par slot dans bank_techno/ :
#   I-1A.yml ... IV-8B.yml (64 fichiers)
# Puis :
td3 send-all bank_techno --port "TD-3-MO"
# Tous les 64 slots de la TD-3 sont flashés en une fois
```

---

## Pitfalls courants

- **`unknown port 'TD-3-MO'`** : le port a un suffixe numérique (`TD-3-MO 8`)
  qui doit être inclus, OU le fragment doit matcher exactement un seul port.
  Vérifier avec `td3 ports`.
- **`pattern must be one of 1A..8B`** : le format du champ `pattern` dans
  le YAML est `1A` à `8B` (chiffre + lettre, pas d'espace, pas de tiret).
- **Pattern joué dans Synthtribe ≠ pattern envoyé** : Synthtribe normalise
  certains champs (triplet + step_count, voir `docs/td3-mo-fr.md`).
- **CC 74 sans effet** : vérifier que TD-3 est en clock source MIDI USB
  (voir procédure dans `docs/td3-mo-fr.md`). Sans ça la TD-3 ignore les
  CC entrants.
- **Slide / accent inaudibles** : ces effets sont prononcés via le séquenceur
  interne de la TD-3 (`START` sur la façade), pas via MIDI Note On/Off live.
  Le Preview Renoise les approxime mais c'est le slot mémoire qui rendra
  les "vrais" 303.
