# Behringer TD-3-MO — Aide-mémoire en français

Extrait des sections les plus utiles du Quick Start Guide officiel
(QSG_BE_0718-ABX_TD-3-MO_WW.pdf), recomposées proprement parce que la mise en
page d'origine éclate les colonnes.

## Réglage de la synchronisation et de l'horloge ★

C'est la section piège : nécessaire si vous voulez piloter la TD-3 en MIDI
(via USB ou DIN). Le sélecteur **n'est pas un switch arrière** mais une
combinaison de touches en façade.

Les boutons 1, 2, 3 et 4 (du clavier de programmation 13 touches, la rangée
du bas) représentent la **source d'horloge** :

| Bouton | Source |
| ------ | ------ |
| 1      | INT (interne, défaut)|
| 2      | MIDI (5-pin DIN) |
| 3      | **USB** |
| 4      | TRIG |

Les boutons 5, 6, 7 et 8 représentent le **rythme** :

| Bouton | Rythme |
| ------ | ------ |
| 5      | 1 PPS |
| 6      | 2 PPQ |
| 7      | 24 PPQ (recommandé) |
| 8      | 48 PPQ |

### Procédure pas-à-pas

1. Appuyez sur **Function**.
2. Assurez-vous qu'aucune séquence n'est en cours de lecture.
3. Appuyez **simultanément** sur **BACK** et **WRITE/NEXT** pour passer en
   mode de réglage de la synchronisation.
4. Les LEDs des sélecteurs 1 à 8 s'allument et celles correspondant aux
   sources d'horloge (1 à 4) et au rythme (5 à 8) clignotent. **Vous
   disposez de 3 secondes** pour effectuer tout changement.
5. Appuyez sur les boutons 1, 2, 3 ou 4 pour modifier la source d'horloge
   (respectivement INT, MIDI, USB ou TRIG).
6. Appuyez sur les boutons 5, 6, 7 ou 8 pour modifier le rythme.
7. Appuyez sur n'importe quel autre bouton ou patientez 3 secondes pour
   sauvegarder les modifications.

→ **Pour piloter la TD-3 par USB MIDI**, choisir source = USB (bouton 3).

## Chemin du signal

1. **VCO** — un oscillateur contrôlé par la tension. WAVEFORM = sawtooth
   inversée ou pulse. TUNE = hauteur générale.
2. **VCF** — filtre passe-bas contrôlé par la tension. Réglages : CUTOFF,
   RESONANCE.
3. **ENVELOPE + DECAY** modulent la fréquence de coupure du VCF. Couplés :
   plus ENVELOPE est élevé, plus DECAY est audible.
4. **ACCENT** agit uniquement sur les notes d'un pattern marquées avec
   accentuation. Pour les TD-3-MO : DECAY-NORMAL et ACCENT séparés.
5. **VCA** puis section **DISTORTION** (si activée). VOLUME contrôle
   casque + sortie principale.

## Sélecteurs de potentiomètres principaux (face avant)

- TUNE : ±1 octave autour du centre, fréquence de référence du VCO.
- CUTOFF : fréquence de coupure du VCF. Fréquences au-dessus = atténuées.
- RESONANCE : amplification autour de Cutoff, jusqu'à auto-oscillation.
- ENVELOPE : modulation du VCF par l'enveloppe.
- DECAY : durée pour que le signal atteigne sa valeur minimale.
- ACCENT : niveau de l'accentuation sur les notes accentuées.
- SOFT ATTACK : durée d'attaque pour les notes non accentuées (TD-3-MO).
- DECAY-NORMAL et ACCENT : enveloppe VCF séparée pour notes normales /
  accentuées (TD-3-MO).
- FILTER TRACKING : suivre la note dans le filtre.
- ACCENT SWEEP : intensité de la résonance accent. 0=off, 1=high reso, 2=normal.
- SWEEP SPEED : vitesse relative de l'accent sweep.
- FILTER FM : amount de modulation FM du filtre.
- OVERDRIVE : distorsion (TD-3-MO).
- VOLUME : sortie générale + casque.
- MUFFLER : soft-clipping VCA sortie. 3 positions : off, mode 1, mode 2.
- SLIDE TIME : durée du portamento (potard 18).
- TEMPO : vitesse de lecture pattern/track.

## Modes de fonctionnement

Bouton **MODE** (potentiomètre 17, 4 positions) :

| Position | Rôle |
| -------- | ---- |
| Track Write | enregistrer une track (chain de patterns) |
| Track Play  | jouer une track |
| Pattern Play | jouer un pattern (lance le séquenceur) |
| Pattern Write | éditer un pattern en mémoire |

Plus le bouton **PITCH MODE** (28) et **TIME MODE** (31) pour entrer les
notes (pitch) puis le timing (note / tie / rest).

## Patchbay arrière (Jacks 3.5 mm TS)

### Entrées
- **Filter in** : ±6V, signal audio à filtrer (la TD-3 sert d'effet filtre).
- Filter FM in : 0V à +12V (FM).
- Filter CV in : 0V à +12V (CV cutoff).
- Accent in : 0V/+12V (CV pour forcer l'accent).
- Slide in : 0V/+3.3V (CV slide).
- Gate in : 0V/+3.3V (gate).
- CV in : +1V à +5V (1V/oct).
- Sync in : > 2.5V.

### Sorties
- Filter out : -400mV à +400mV (sortie du VCF avant VCA).
- Accent out : 0V/+6V.
- Gate out : 0V/+12V.
- CV out : +1V à +5V (1V/octave).

## MIDI (officiel)

- **CC 74** : Filter Cutoff (seul CC officiellement implémenté).
- Pitch Bend.
- Note On/Off, All Notes Off.
- MIDI Clock : Timing Clock (F8), Start (FA), Continue (FB), Stop (FC).

Pas de NRPN. Resonance, env mod, decay, accent, tune ne sont **pas**
contrôlables en MIDI — uniquement par les potards de la façade.

SysEx exhaustif (non documenté officiellement par Behringer mais
reverse-engineered) : voir `src/td3/config.py` dans ce dépôt.
