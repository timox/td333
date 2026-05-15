# Bibliothèque de patterns TD-3

Patterns acid/303 génériques, prêts à envoyer sur la TD-3. Ce sont des
riffs "dans le style de" (gammes, rythmiques, conventions 303) — pas des
transcriptions de morceaux protégés.

| Fichier | Caractère |
|---|---|
| `01_acid_classic.yml` | Walking bass C→G, slides + accents temps forts |
| `02_rolling_16th.yml` | Une note martelée, accents syncopés (hypnotique) |
| `03_octave_jump.yml` | Saut d'octave TB-303 classique |
| `04_minor_groove.yml` | Gamme mineure de C, rests pour le swing |
| `05_phrygian_dark.yml` | Couleur sombre (b2), slides tendus |
| `06_triplet_swing.yml` | Ternaire (triplet=true, 12 steps utiles) |
| `07_staccato_pluck.yml` | Notes sèches espacées, zéro slide |
| `08_long_slide_riser.yml` | Montée legato C1→C4 (build-up / transition) |

## Envoyer un pattern

```bash
td3 send patterns/library/01_acid_classic.yml --port "TD-3-MO"
```

Tous écrivent par défaut dans le groupe **I** (slots 1A à 8A). Modifier
le champ `group` / `pattern` du YAML pour cibler un autre slot, ou
utiliser `td3 send-all patterns/library --port "TD-3-MO"` pour flasher
les 8 d'un coup dans le groupe I.

Ensuite sur la TD-3 : MODE = PATTERN PLAY, GROUP = I, PATTERN A,
Selector 1-8, START.

Côté **tool Renoise**, on peut aussi pointer le dossier *Bibliothèque*
sur `patterns/library/` : ces `.yml` apparaissent directement dans le
popup et se chargent dans la grille (format auto-détecté).

## Convention

- Notes en MIDI standard (C4 = MIDI 60). Plage TD-3 = **C1..C4**.
- Flags : `accent`, `slide`, `tie`, `rest` (ordre libre).
- `-` = step silencieux (rest avec pitch placeholder).
- `<pitch> rest` = rest avec pitch fantôme préservé (round-trip).

## Contribuer

Ajoutez vos patterns au format YAML ici. Garder un préfixe numérique
pour l'ordre, un nom descriptif, et un commentaire d'entête expliquant
le caractère du pattern. Vérifier le round-trip :

```bash
td3 yaml-to-syx patterns/library/votre_pattern.yml --out /tmp/t.syx
td3 syx-to-yaml /tmp/t.syx --out /tmp/back.yml
diff <(grep -v '^#' patterns/library/votre_pattern.yml) /tmp/back.yml
```
