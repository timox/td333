# Behringer TD-3-MO — Guide de référence en français

Traduction synthétique et recomposée du *Quick Start Guide* officiel
Behringer (QSG_BE_0718-ABX_TD-3-MO_WW, multi-langue mais éclaté en colonnes
peu lisibles), enrichie des informations utiles pour piloter la TD-3-MO en
MIDI / SysEx (non documentées par Behringer).

## Vue d'ensemble

La TD-3-MO est un synthétiseur de basse analogique monophonique inspiré
de la Roland TB-303. La variante **MO** ajoute des fonctionnalités issues
des mods Devil Fish (envelope decay séparé normal/accent, soft attack,
filter FM, overdrive, sub-oscillator, plage de filtre étendue).

- Voix : monophonique, polyphonie 1
- Oscillateurs : 1 VCO (square ou sawtooth inversée) + 1 sub-oscillator
- Filtre : 1 VCF passe-bas, plage étendue avec FM
- Enveloppes : 1, avec decay séparé pour notes normales et accentuées
- Séquenceur : 4 groupes × 16 patterns × 16 steps + 7 tracks (chaînes
  de patterns)
- Connectique : MIDI DIN, USB-B, audio 6,35", casque 3,5", patchbay
  CV/Gate 3,5" TS

## Chemin du signal

1. **VCO** — oscillateur contrôlé par la tension. WAVEFORM = sawtooth
   inversée ou pulse. TUNE = hauteur générale (±1 octave autour du centre).
2. **VCF** — filtre passe-bas. CUTOFF = fréquence de coupure (les
   fréquences au-dessus sont atténuées). RESONANCE = amplification autour
   de la fréquence de coupure, peut auto-osciller au max.
3. **ENV MOD + DECAY** — l'enveloppe module la fréquence de coupure.
   Plus ENV MOD est haut, plus DECAY est audible.
4. **ACCENT** — les notes du pattern marquées "accent" reçoivent un
   traitement spécifique (volume + filtre boostés). TD-3-MO sépare le
   DECAY normal et le DECAY accent.
5. **VCA** — étage de gain final, suivi de la section **DISTORTION** si
   activée.
6. **VOLUME** — niveau général + casque.

## Face avant — pots et switches

### Synthèse (1-15)

| # | Contrôle | Rôle |
|---|---|---|
| 1 | TUNE | Fréquence du VCO (±1 octave) |
| 2 | CUTOFF | Fréquence de coupure du VCF |
| 3 | RESONANCE | Résonance du VCF |
| 4 | ENV MOD / ENVELOPE | Profondeur de modulation du VCF par l'enveloppe |
| 5 | DECAY (et DECAY-ACCENT sur MO) | Durée de décroissance de l'enveloppe |
| 6 | ACCENT | Niveau de l'accentuation |
| 7 | SOFT ATTACK (MO) | Durée d'attaque pour notes non-accentuées |
| 8 | GATE LED | Rouge = gate actif, vert = mode poly-chain |
| 9 | DECAY-NORMAL / DECAY-ACCENT (MO) | Decay séparé pour notes normales / accentuées |
| 10 | FILTER TRACKING (MO) | Le filtre suit la note jouée |
| 11 | OVERDRIVE (MO) | Niveau de distorsion (off à fond = signal coupé) |
| 12 | SUB OSC | On/off sub-oscillator |
| 14 | TEMPO | Vitesse de lecture des patterns/tracks |
| 15 | WAVEFORM | Sawtooth inversée ou pulse (carrée) |

### Séquenceur (16-17)

| # | Contrôle | Rôle |
|---|---|---|
| 16 | TRACK/PATTERN GROUP | Sélectionne TRACK 1-7 (en mode Track) ou PATTERN GROUP I-IV (en mode Pattern) |
| 17 | MODE | 4 positions : Track Write / Track Play / Pattern Play / Pattern Write |

### Patterns 18-26

| # | Contrôle | Rôle |
|---|---|---|
| 18 | SLIDE TIME | Durée du portamento |
| 19 | SWEEP SPEED | Vitesse de l'accent sweep |
| 20 | ACCENT SWEEP | 0=off, 1=high reso, 2=normal |
| 21 | FILTER FM | Modulation FM du filtre par la sortie audio |
| 22 | VOLUME | Sortie générale + casque |
| 23 | MUFFLER | 3 positions : off, mode 1 (atténue hautes fréquences), mode 2 (plus prononcé) |
| 24 | ACCENT | Maintenu = force l'accent sur tous les steps |

### Clavier 13 touches (29) et contrôles d'entrée (27-40)

- **29 — 13-NOTE KEYBOARD** : disposition clavier (1 octave + un C aigu).
  Les 8 touches du bas servent aussi de sélecteurs (Selector 1-8) pour
  les patterns, tracks, et réglages.
- **27 — D.C./BAR RESET/CLEAR** : efface un pattern (en Pattern Write),
  reset au début (en Track Play), signale fin de track (en Track Write).
- **28 — PITCH MODE** : entrer les notes dans un pattern.
- **30 — LED TIME MODE** : allumée quand on est en TIME MODE.
- **31 — TIME MODE ON/OFF** : entrer le timing (note / tie / rest) après
  les pitches.
- **32 — BACK** : revenir au step précédent. Combiné avec WRITE/NEXT
  pour entrer en mode réglage SYNC/CLOCK.
- **33 — START/STOP** : lance/arrête la lecture.
- **34 — LED NORMAL MODE** : allumée en mode normal.
- **35 — TRANSPOSE DOWN/NOTE/STEP** : transpose -1 octave en PITCH, entre
  une note en TIME, fixe le nombre de steps d'un pattern.
- **36 — D.S./WRITE/NEXT/TAP** : écrit un pattern dans une track, avance
  d'un step, tape le tempo manuellement.
- **37 — TRANSPOSE UP/TIE/TRIPLET** : +1 octave en PITCH, ajoute une tie
  en TIME, met le pattern en mode triplet.
- **38 — ACCENT / PATTERN A** : ajoute un accent à une note (PITCH MODE),
  sélectionne un pattern A1-A8 (PLAY).
- **39 — SLIDE / PATTERN B** : ajoute un slide à une note, sélectionne
  un pattern B1-B8.
- **40 — FUNCTION** : touche de modification globale (combiné avec d'autres).

## Patchbay (jacks 3,5 mm TS, standard Eurorack)

### Entrées

| Jack | Niveau | Usage |
|---|---|---|
| **Filter in** | ±6 V (audio line) | Source audio externe à filtrer par le VCF de la TD-3 |
| **Filter FM in** | 0..+12 V | CV de modulation FM du filtre |
| **Filter CV in** | 0..+12 V | CV de pilotage cutoff |
| **Accent in** | 0 / +12 V | Trigger pour forcer l'accent en live |
| **Slide in** | 0 / +3,3 V | Trigger pour forcer le slide |
| **Gate in** | 0 / +3,3 V | Gate externe (l'enveloppe se déclenche dessus) |
| **CV in** | +1..+5 V | Pitch CV, 1V/octave (standard Eurorack) |
| **Sync in** | > 2,5 V | Clock externe pour synchroniser le séquenceur |

### Sorties

| Jack | Niveau | Usage |
|---|---|---|
| **Filter out** | -400..+400 mV | Sortie du VCF avant le VCA (filtre seul) |
| **Accent out** | 0 / +6 V | Gate qui s'active sur les steps accentués |
| **Gate out** | 0 / +12 V | Gate principal du séquenceur |
| **CV out** | +1..+5 V (1V/oct) | Pitch CV — pour piloter un VCO externe |

### Audio principal

- **OUTPUT** (1/4" TRS) : sortie ligne mono.
- **HEADPHONES** (3,5 mm TRS) : casque avec volume séparé.

### MIDI

- **MIDI IN** (5-pin DIN) : entrée notes / clock / SysEx.
- **MIDI OUT/THRU** (5-pin DIN) : sortie + relay du MIDI in.
- **USB B** : USB Class-Compliant MIDI (IN + OUT). C'est sur ce port que
  Synthtribe et notre tool communiquent.

### Alimentation

- **DC INPUT** : adaptateur 9 V DC 670 mA fourni.
- **POWER** : bouton on/off (push button).

## Réglage de la synchronisation et de l'horloge ★

Section critique : nécessaire si vous voulez piloter la TD-3 par MIDI
USB ou DIN. Le sélecteur de source d'horloge **n'est pas un switch
arrière** mais une combinaison de touches façade.

Les **Selector 1-4** (4 touches blanches du bas du clavier) représentent
la source d'horloge :

| Selector | Source |
|---|---|
| 1 | INT (interne, défaut usine) |
| 2 | MIDI (DIN) |
| 3 | **USB** |
| 4 | TRIG (Sync in jack) |

Les **Selector 5-8** représentent le rythme (PPQN) :

| Selector | Rythme |
|---|---|
| 5 | 1 PPS (1 pulse par seconde, sync analog vintage) |
| 6 | 2 PPQ |
| 7 | 24 PPQ (recommandé pour MIDI clock) |
| 8 | 48 PPQ |

### Procédure pas-à-pas

1. Appuyer sur **FUNCTION**.
2. S'assurer qu'aucune séquence n'est en lecture (STOP préalable).
3. Appuyer **simultanément** sur **BACK** et **WRITE/NEXT** → mode SYNC.
4. Les LEDs Selector 1-8 s'allument, la source actuelle (1-4) et le
   rythme actuel (5-8) clignotent. **Vous avez 3 secondes** pour
   changer.
5. Appuyer sur **Selector 1-4** pour la source d'horloge.
6. Appuyer sur **Selector 5-8** pour le rythme.
7. Appuyer sur une autre touche ou attendre 3 s pour valider.

→ **Pour piloter par USB MIDI** : Selector 3 (USB) + Selector 7 (24 PPQ).

## Écrire un pattern

### Préparation

1. **MODE** sur **PATTERN WRITE**.
2. **TRACK/PATTERN GROUP** sur I, II, III ou IV.
3. **FUNCTION** : la LED NORMAL MODE s'allume, une LED PATTERN clignote.
4. Choisir le slot : Selector 1-8 + **ACCENT/PATTERN A** (pour 1A-8A)
   ou **SLIDE/PATTERN B** (pour 1B-8B). La LED choisie clignote.

### Définir la longueur

5. (Optionnel) STOP préalable s'il y avait un pattern en lecture.
6. **FUNCTION** maintenu + appuyer N fois sur STEP pour fixer N steps
   (par défaut 16). Pour 8 steps : Function + 8 appuis STEP.

### Entrer les pitches (PITCH MODE)

7. **PITCH MODE** : la LED s'allume.
8. Appuyer sur les 13 touches du clavier pour entrer les notes une par
   une (jusqu'à atteindre le nombre de steps défini).
9. Octave : maintenir **TRANSPOSE UP** ou **TRANSPOSE DOWN** + appuyer
   sur la note → décale d'une octave.

### Entrer le timing (TIME MODE)

10. **TIME MODE** : la LED s'allume.
11. Pour chaque step on choisit parmi 3 options :
    - **NOTE** (TRANSPOSE DOWN) : joue la pitch entrée
    - **TIE** (TRANSPOSE UP) : tient la note précédente (no retrigger)
    - **REST** (D.C./CLEAR) : silence

    Exemple pour 16 notes : `Note, Rest, Rest, Note, Tie, Note, Note,
    Tie, Note, Note, Tie, Note, Note, Note, Tie, Note`.

12. Quand on atteint le nombre de notes du pattern, TIME MODE est
    quitté automatiquement.

### Ajouter accents et slides

13. Toujours en PATTERN WRITE : **PITCH MODE** ON. Appuyer plusieurs
    fois sur **WRITE/NEXT** pour avancer step par step (joue la note).
14. Sur la note à modifier : maintenir **WRITE/NEXT** + appuyer sur
    **ACCENT** et/ou **SLIDE** pour ajouter/retirer le flag.
15. Si vous dépassez la note voulue, appuyer **BACK** puis re-maintenir
    WRITE/NEXT.

### Notes spéciales

- Si la dernière note d'un pattern a un slide :
  - En **TRACK PLAY** : le slide glisse vers le pattern suivant de la track.
  - En **PATTERN WRITE/PLAY** mono-pattern : le slide glisse vers le début
    du même pattern.
- Le potard **ACCENT** n'agit que sur les notes marquées accent.

## Méthode alternative — tap timing

Au lieu d'entrer NOTE/TIE/REST en TIME MODE, on peut taper le rythme :

1. STOP la séquence.
2. **CLEAR** : déclenche un métronome avec un downbeat au début.
3. **TAP** : tapez le rythme voulu (TEMPO peut être baissé pour aider).
4. Pour ajouter du sustain : maintenir TAP.
5. Répéter jusqu'à ce que ça sonne bien.

## Jouer un pattern

1. **MODE** = PATTERN PLAY.
2. **TRACK/PATTERN GROUP** sur le groupe voulu (I-IV).
3. **FUNCTION** : LED NORMAL MODE allumée.
4. Selector 1-8 + PATTERN A ou B.
5. **START/STOP** → lance.
6. Ajuster TEMPO et knobs synthèse en live.
7. Transposition live : maintenir **PITCH MODE** + appuyer sur une touche
   → le pattern est joué transposé sur cette tonalité au prochain wrap.

### Enchaîner deux patterns

Pendant la lecture, appuyer sur un autre Selector + A/B : ça enchaîne
au prochain wrap. Pour jouer un range de patterns consécutifs : maintenir
le premier Selector + presser le second → tous les patterns entre les
deux sont joués en boucle.

## Mode Track (chaînes de patterns)

Une track = séquence ordonnée de patterns. La TD-3-MO a 7 tracks :

- Track 1, 2 → groupe I
- Track 3, 4 → groupe II
- Track 5, 6 → groupe III
- Track 7 → groupe IV

### Écrire une track

1. **MODE** = TRACK WRITE.
2. **TRACK/PATTERN GROUP** sur la track désirée (1-7).
3. **CLEAR** pour reset au début.
4. **START/STOP** → la track commence à jouer le pattern courant
   (l'écriture ne se fait qu'en lecture).
5. Sélectionner le 1er pattern : appuyer Selector + A ou B.
6. **WRITE/NEXT** pour ajouter ce pattern à la track.
7. Recommencer pour les patterns suivants. Pour transposer un pattern
   dans la track : maintenir **PITCH MODE** + appuyer sur une touche.
8. **WRITE/NEXT** pour valider chaque pattern.
9. Sur le dernier pattern : **CLEAR** pour marquer la fin de la track.
10. **WRITE/NEXT**.
11. **START/STOP** pour finir.

### Lire une track

1. **MODE** = TRACK PLAY.
2. **TRACK/PATTERN GROUP** sur la track.
3. **CLEAR** pour reset.
4. **START/STOP**.

### Supprimer un pattern d'une track

1. **MODE** = TRACK WRITE.
2. **TRACK/PATTERN GROUP** sur la track.
3. Sélectionner le pattern à supprimer : maintenir **FUNCTION** +
   PATTERN N (par ex. PATTERN 3 = note E).
4. Supprimer : maintenir **FUNCTION** + **DEL** (C# du clavier).
5. **MODE** = TRACK PLAY, **CLEAR**, **TAP**, **START/STOP** pour
   valider.

### Insérer un pattern dans une track

1. TRACK WRITE.
2. Sélectionner la position : FUNCTION + PATTERN N.
3. Insérer : FUNCTION + **INS** (D# du clavier).
4. START/STOP — le pattern ajouté joue.
5. Sélectionner le nouveau pattern : Selector + A ou B.
6. TAP pour valider.
7. STOP, TRACK PLAY, CLEAR, START/STOP pour vérifier.

### Écraser une track

Pas besoin d'effacer avant : démarrer en TRACK WRITE et entrer la
nouvelle séquence. Si la nouvelle track est plus courte, à la fin du
dernier pattern entré, la track boucle automatiquement.

## MIDI (officiellement documenté)

D'après la Quick Start Guide page 64-65 :

### Messages canal

| Status | Octets | Description |
|---|---|---|
| 8n / 9n | note + velocity | Note Off / Note On |
| Bn 7B 00 | — | All Notes Off |
| Bn 4A xx | xx ∈ 0-127 | **Filter Cutoff (CC 74)** ← le seul CC |
| En bb bb | 0-3FFF | Pitch Bend |

### Real-Time

| Status | Description |
|---|---|
| F8 | Timing Clock |
| FA | Start |
| FB | Continue |
| FC | Stop |

**Pas de NRPN. Pas de CC pour resonance / env mod / decay / accent /
tune** — tous ces paramètres sont uniquement contrôlables par les potards
de la façade.

## MIDI / SysEx (reverse engineered)

Au-delà du Quick Start Guide, la TD-3-MO accepte tout un protocole SysEx
non documenté par Behringer. Header manufacturer : `F0 00 20 32 00 01 0A`.
Opcodes complets dans [`src/td3/config.py`](../src/td3/config.py) et
[`src/td3/sysex.py`](../src/td3/sysex.py).

Résumé des opcodes les plus utiles :

| Opcode | Direction | Rôle |
|---|---|---|
| `0x77` | TX | Request pattern (réponse 0x78) |
| `0x78` | TX/RX | Pattern data (112 octets payload) |
| `0x75` | TX | Request config (réponse 0x76) |
| `0x0E` | TX | Set MIDI channels |
| `0x0F` | TX | Set MIDI input transpose |
| `0x12` | TX | Set key priority |
| `0x1B` | TX | Set clock source (équivalent SysEx du switch SYNC/CLOCK façade) |
| `0x1C` | TX | Set accent velocity threshold (0-127) |
| `0x7D` | TX | Reset to factory defaults |
| `0x01` | RX | ACK générique (en réponse aux SET) |
| `0x08` / `0x09` | TX/RX | Get firmware version |
| `0x04` / `0x05` | TX/RX | Get model name |
| `0x06` / `0x07` | TX/RX | Get product name |
| `0x50` | TX | Hardware test mode (la TD-3 émet alors de l'aftertouch reflétant les positions des knobs) |
| `0x03 0x30` | TX | Entrer en mode DFU (firmware update USB PID 1227) |

## Spécifications techniques

| Catégorie | Valeur |
|---|---|
| Voix | Monophonique analogique |
| Oscillateurs | 1 VCO (square / saw inversée) |
| Filtre | 1 VCF passe-bas, plage étendue (MO) |
| Enveloppes | 1, decay normal/accent séparé (MO) |
| Alimentation | 9 V DC 670 mA, adaptateur externe fourni |
| Consommation | 4 W max |
| Température opérante | 5 à 40 °C |
| Dimensions (H × L × P) | 56 × 305 × 165 mm |
| Poids | 0,9 kg |
| USB | Class-compliant 2.0 Type B |
| OS supportés | Windows 7+, macOS 10.6.8+ |
| Sortie ligne | 1/4" TRS, max +8 dBu, impédance 1,5 kΩ |
| Sortie casque | 3,5 mm TRS, max 50 mW / 32 Ω |

## Système de fichiers et formats

- **Patterns** : 4 groupes × 16 patterns × jusqu'à 16 steps en mémoire
  non volatile. Total 64 patterns. Format binaire 112 octets par pattern
  (voir `src/td3/pattern.py`).
- **Tracks** : 7 tracks de patterns chaînés, en mémoire non volatile.
  Format non documenté publiquement (non utilisé par Synthtribe Export).
- **`.sqs`** : fichier de banque produit par Synthtribe. Magic
  `87 43 91 02`, header UTF-16BE produit + version, puis 64 records de
  124 octets (group/pattern/size/112 bytes data).
- **`.seq`** : fichier d'export d'un pattern unique par Synthtribe. Magic
  `23 98 54 76`, même payload mais un seul record.
