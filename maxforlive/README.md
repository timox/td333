# TD-3 Pattern Editor — Max for Live

Portage Max for Live de l'éditeur de pattern SysEx du tool Renoise
(`renoise/com.timox.td3-renoise.xrnx/`). Même logique : programmer une
pattern 16 pas et l'écrire dans un slot mémoire de la **Behringer TD-3 /
TD-3-MO** en SysEx, ou la relire (Read).

## Fichiers

| Fichier | Rôle |
|---|---|
| `td3.js` | codec pur (port fidèle de `td3.lua`). Marche dans `[js]` Max **et** en Node. |
| `td3_device.js` | glu Max : état du pattern, build/parse SysEx, pilotage UI. |
| `TD-3 Pattern Editor.maxpat` | patcher SysEx (UI + câblage MIDI). |
| `td3_live.js` | MIDI Effect « live » : accent/slide/cutoff, pas de SysEx. |
| `TD-3 Live.maxpat` | patcher du device live (TD-3 jouée en instrument). |
| `test_td3.mjs` | test Node : compare `td3.js` à la lib Python **byte-exact**. |
| `test_td3_live.mjs` | test Node : transformation accent/slide/cutoff. |

Deux devices distincts :
- **TD-3 Pattern Editor** : programme/lit un slot mémoire (SysEx).
- **TD-3 Live** : joue la TD-3 comme module de son (accent = vélocité ≥
  seuil, slide = legato monophonique, cutoff CC74). Aucun stockage.

## Vérification du codec (sans Max)

```bash
pip install -e .            # lib td3 de référence
node maxforlive/test_td3.mjs
```

→ vérifie que la SysEx Write/Request produite par `td3.js` est
**identique au bit près** à celle de la lib Python, plus le round-trip
encode→decode. ✅ testé, tout passe.

## Monter le device dans Ableton Live

> ⚠️ Le patcher (`.maxpat`) **n'a pas pu être testé** ici (pas de Max
> dans l'environnement). Le codec, lui, est validé. Étapes :

1. Ableton Live → piste MIDI → glisser un **Max MIDI Effect** vide.
2. Cliquer **Edit** (ouvre Max). Menu *File → Open* →
   `TD-3 Pattern Editor.maxpat`, copier tous les objets dans le device,
   ou *Save As* le patcher en `.amxd` dans le dossier User Library.
3. Garder `td3.js` et `td3_device.js` **à côté** du `.amxd`
   (Max les résout par nom).
4. Régler la sortie MIDI du `[midiout]` / de la piste vers le port
   **TD-3**. L'entrée (`[midiin]`) reçoit les dumps Read.

## Utilisation

- **umenu groupe / pattern** : slot cible (I..IV × 1A..8B).
- **matrixctrl** 16×3 : ligne 0 = pas actif (sinon rest), ligne 1 =
  accent, ligne 2 = slide.
- **multislider** : hauteur 0..36 = C1..C4 (+ *octave shift*).
- **triplet / steps** : mode triplet et nombre de pas (1..16).
- **write** : envoie la SysEx d'écriture du slot. Le hex s'affiche.
- **request** : demande un Read ; le dump reçu repeint l'UI.
- **clear** : remet tout en rest. **dump** : imprime le hex (fenêtre Max).

## Limites / parité

- Couvre le **TD-3 Pattern Editor** (SysEx). Le mode *MIDI-live
  32 pas + FX* du tool Renoise n'est pas (encore) porté.
- Sémantique identique à `td3.lua` : pitch storage = MIDI−12 clampé
  C1..C4, hold mask inversé, quirk triplet (step_count→15).
