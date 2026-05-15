"""CLI: simplify writing TD-3 MIDI patterns from YAML."""
from __future__ import annotations

import os
import sys
from pathlib import Path

import click

from .pattern import Pattern
from .sqs import SQSFile, read_seq, read_sqs, write_sqs
from .sysex import iter_sysex, pattern_to_sysex, request_pattern, sysex_to_pattern
from .yaml_io import (_GROUP_LABELS, _GROUP_LABEL_LOOKUP, format_pattern_label,
                      parse_pattern_label, pattern_from_yaml, pattern_to_yaml)


def _parse_slot(slot: str) -> tuple[int, int]:
    """'IV-1A' / 'I-3B' / 'II 8A' → (group_idx 0..3, pattern_idx 0..15)."""
    s = slot.replace("-", " ").replace("/", " ").split()
    if len(s) != 2:
        raise click.ClickException(f"slot invalide {slot!r} — format attendu: IV-1A")
    g = _GROUP_LABEL_LOOKUP.get(s[0].upper())
    if g is None:
        raise click.ClickException(f"groupe invalide dans {slot!r} (I..IV)")
    try:
        return g, parse_pattern_label(s[1])
    except ValueError as e:
        raise click.ClickException(str(e)) from e


def _filename_for(p: Pattern) -> str:
    return f"{_GROUP_LABELS[p.group]}-{format_pattern_label(p.number)}.yml"


def _sorted_pattern_files(directory: Path) -> list[Path]:
    """Collect pattern YAMLs sorted by (group, pattern) regardless of label width."""
    files = [f for f in directory.glob("*.yml") if f.stem != "_meta"]
    def key(f: Path):
        try:
            p = pattern_from_yaml(f.read_text())
            return (p.group, p.number)
        except Exception:
            return (99, 99)
    return sorted(files, key=key)


@click.group()
def main() -> None:
    """Simplifie l'édition des patterns MIDI de la TD-3 (YAML ↔ .sqs ↔ SysEx)."""


# ---- .sqs / YAML round-trip ------------------------------------------------

@main.command()
@click.argument("sqs_path", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option("--out", "out_dir", type=click.Path(file_okay=False, path_type=Path),
              default=Path("patterns"), show_default=True,
              help="Dossier de sortie pour les YAML.")
def unpack(sqs_path: Path, out_dir: Path) -> None:
    """Extrait chaque pattern d'un .sqs vers un YAML lisible."""
    sqs = read_sqs(sqs_path.read_bytes())
    out_dir.mkdir(parents=True, exist_ok=True)
    for p in sqs.patterns:
        (out_dir / _filename_for(p)).write_text(pattern_to_yaml(p))
    meta = f"product: {sqs.product}\nversion: {sqs.version}\n"
    (out_dir / "_meta.yml").write_text(meta)
    click.echo(f"wrote {len(sqs.patterns)} patterns to {out_dir}/")


@main.command()
@click.argument("yaml_dir", type=click.Path(exists=True, file_okay=False, path_type=Path))
@click.option("--out", "out_path", type=click.Path(dir_okay=False, path_type=Path),
              default=Path("dump.sqs"), show_default=True,
              help="Fichier .sqs à produire.")
@click.option("--product", default="TD-3-MO", show_default=True)
@click.option("--version", default="2.0.1",  show_default=True)
def pack(yaml_dir: Path, out_path: Path, product: str, version: str) -> None:
    """Recompacte un dossier de YAML en un .sqs (64 patterns attendus)."""
    files = _sorted_pattern_files(yaml_dir)
    patterns = [pattern_from_yaml(f.read_text()) for f in files]
    if len(patterns) != 64:
        click.echo(f"warning: got {len(patterns)} patterns (expected 64)", err=True)
    sqs = SQSFile(product=product, version=version, patterns=patterns)
    out_path.write_bytes(write_sqs(sqs))
    click.echo(f"wrote {out_path} ({out_path.stat().st_size} bytes)")


# ---- single-pattern conversions -------------------------------------------

@main.command(name="yaml-to-syx")
@click.argument("yaml_path", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option("--out", "out_path", type=click.Path(dir_okay=False, path_type=Path),
              default=None, help="Fichier .syx (par défaut: même nom que l'YAML).")
def yaml_to_syx(yaml_path: Path, out_path: Path | None) -> None:
    """Génère un fichier .syx (SysEx F0..F7) à partir d'un YAML."""
    p = pattern_from_yaml(yaml_path.read_text())
    out = out_path or yaml_path.with_suffix(".syx")
    out.write_bytes(pattern_to_sysex(p))
    click.echo(f"wrote {out} ({out.stat().st_size} bytes)")


@main.command(name="syx-to-yaml")
@click.argument("syx_path", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option("--out", "out_path", type=click.Path(dir_okay=False, path_type=Path),
              default=None)
def syx_to_yaml(syx_path: Path, out_path: Path | None) -> None:
    """Décode un .syx (un ou plusieurs messages) vers YAML."""
    buf = syx_path.read_bytes()
    msgs = list(iter_sysex(buf))
    if not msgs:
        raise click.ClickException("no SysEx message found")
    if len(msgs) == 1 and out_path:
        p = sysex_to_pattern(msgs[0])
        out_path.write_text(pattern_to_yaml(p))
        click.echo(f"wrote {out_path}")
    else:
        out_dir = out_path or syx_path.parent
        out_dir.mkdir(parents=True, exist_ok=True) if out_path else None
        for msg in msgs:
            p = sysex_to_pattern(msg)
            (Path(out_dir) / _filename_for(p)).write_text(pattern_to_yaml(p))
        click.echo(f"wrote {len(msgs)} patterns to {out_dir}/")


# ---- live MIDI -------------------------------------------------------------

def _require_mido():
    try:
        import mido  # noqa: F401
        return __import__("mido")
    except ImportError as e:
        raise click.ClickException(
            "live MIDI requires 'mido' + 'python-rtmidi'. "
            "Install with: pip install 'td3[midi]'"
        ) from e


@main.command()
def ports() -> None:
    """Liste les ports MIDI disponibles."""
    mido = _require_mido()
    click.echo("Input ports:")
    for n in mido.get_input_names():
        click.echo(f"  {n}")
    click.echo("Output ports:")
    for n in mido.get_output_names():
        click.echo(f"  {n}")


@main.command()
@click.argument("yaml_path", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option("--port", required=True, help="Nom (ou fragment) du port MIDI de sortie.")
def send(yaml_path: Path, port: str) -> None:
    """Envoie un pattern YAML vers la TD-3 via MIDI SysEx."""
    mido = _require_mido()
    target = _resolve_port(mido.get_output_names(), port)
    p = pattern_from_yaml(yaml_path.read_text())
    msg = mido.Message.from_bytes(pattern_to_sysex(p))
    with mido.open_output(target) as out:
        out.send(msg)
    click.echo(f"sent pattern {_GROUP_LABELS[p.group]}-{format_pattern_label(p.number)} to {target!r}")


@main.command(name="seq-to-yaml")
@click.argument("seq_path", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option("--out", "out_path", type=click.Path(dir_okay=False, path_type=Path), default=None)
@click.option("--slot", default="I-1A", show_default=True,
              help="Slot cible inscrit dans le YAML (le .seq ne contient pas l'info).")
def seq_to_yaml(seq_path: Path, out_path: Path | None, slot: str) -> None:
    """Convertit un .seq (export Synthtribe d'un pattern unique, trouvable
    sur le net) en YAML éditable."""
    g, n = _parse_slot(slot)
    p = read_seq(seq_path.read_bytes(), group=g, number=n)
    out = out_path or seq_path.with_suffix(".yml")
    out.write_text(pattern_to_yaml(p))
    click.echo(f"wrote {out}  (slot {slot})")


@main.command(name="send-seq")
@click.argument("seq_path", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option("--port", required=True, help="Nom (ou fragment) du port MIDI de sortie.")
@click.option("--slot", default="I-1A", show_default=True,
              help="Slot cible sur la TD-3 (le .seq ne contient pas l'info).")
def send_seq(seq_path: Path, port: str, slot: str) -> None:
    """Injecte un fichier .seq trouvé ailleurs directement dans un slot
    de la TD-3 via SysEx."""
    mido = _require_mido()
    target = _resolve_port(mido.get_output_names(), port)
    g, n = _parse_slot(slot)
    p = read_seq(seq_path.read_bytes(), group=g, number=n)
    with mido.open_output(target) as out:
        out.send(mido.Message.from_bytes(pattern_to_sysex(p)))
    click.echo(f"sent {seq_path.name} → slot {_GROUP_LABELS[p.group]}-"
               f"{format_pattern_label(p.number)} on {target!r}")


@main.command(name="send-track")
@click.argument("track_path", type=click.Path(exists=True, dir_okay=False, path_type=Path))
@click.option("--port", required=True, help="Nom (ou fragment) du port MIDI de sortie.")
def send_track(track_path: Path, port: str) -> None:
    """Flashe les patterns d'une track (liste ordonnée de YAML) sur des slots consécutifs, puis affiche l'ordre de chaînage à reproduire sur la façade TD-3.

    Format track.yml :

        name: "Mon set acid"
        group: I            # I..IV — tous les patterns vont dans ce groupe
        patterns:
          - patterns/library/01_acid_classic.yml
          - patterns/library/03_octave_jump.yml
          - patterns/library/02_rolling_16th.yml

    Le chaînage track lui-même ne peut PAS être écrit par SysEx (aucun
    opcode connu) : on écrit chaque pattern dans son slot et on imprime
    la séquence à entrer manuellement en mode TRACK WRITE sur la TD-3.
    """
    import yaml as _yaml
    mido = _require_mido()
    target = _resolve_port(mido.get_output_names(), port)
    doc = _yaml.safe_load(track_path.read_text())
    if not isinstance(doc, dict) or "patterns" not in doc:
        raise click.ClickException("track.yml doit contenir 'patterns: [...]'")

    name = doc.get("name", track_path.stem)
    group_label = str(doc.get("group", "I")).upper()
    group_idx = {"I": 0, "II": 1, "III": 2, "IV": 3}.get(group_label)
    if group_idx is None:
        raise click.ClickException(f"group invalide : {group_label!r} (I..IV)")

    files = doc["patterns"]
    if len(files) > 16:
        raise click.ClickException(f"{len(files)} patterns : max 16 par groupe")

    base = track_path.parent
    slots: list[str] = []
    with mido.open_output(target) as out:
        for i, rel in enumerate(files):
            fp = (base / rel) if not Path(rel).is_absolute() else Path(rel)
            if not fp.exists():
                fp = Path(rel)  # fallback : relatif au cwd
            p = pattern_from_yaml(Path(fp).read_text())
            p.group = group_idx
            p.number = i  # slots 0..7 = 1A..8A, 8..15 = 1B..8B
            out.send(mido.Message.from_bytes(pattern_to_sysex(p)))
            label = format_pattern_label(i)
            slots.append(label)
            click.echo(f"  slot {group_label}-{label}  ←  {Path(rel).name}")

    click.echo(f"\nTrack {name!r} : {len(files)} patterns écrits dans le groupe {group_label}.")
    track_no = {0: "1 ou 2", 1: "3 ou 4", 2: "5 ou 6", 3: "7"}[group_idx]
    click.echo(
        "\nPour chaîner sur la TD-3 (le chaînage n'est pas pilotable en SysEx) :\n"
        f"  1. MODE = TRACK WRITE, TRACK/PATTERN GROUP = track {track_no} (groupe {group_label})\n"
        "  2. CLEAR pour reset\n"
        "  3. START/STOP pour lancer l'écriture\n"
        "  4. Pour chaque pattern dans l'ordre, sélectionner Selector + A/B\n"
        f"     puis WRITE/NEXT. Ordre : {' → '.join(slots)}\n"
        "  5. Sur le dernier : CLEAR (marque la fin) puis WRITE/NEXT\n"
        "  6. START/STOP pour terminer. MODE = TRACK PLAY pour jouer."
    )


@main.command()
@click.option("--port", required=True, help="Nom du port MIDI d'entrée (loopMIDI/IAC pour intercepter Synthtribe).")
@click.option("--timeout", default=8.0, show_default=True, help="Délai max en secondes par contrôle.")
@click.option("--out", "out_path", type=click.Path(dir_okay=False, path_type=Path),
              default=Path("td3_cc_map.json"), show_default=True,
              help="Fichier JSON de sortie.")
def sniff(port: str, timeout: float, out_path: Path) -> None:
    """Capture passive : on écoute ce qui arrive sur un port MIDI pendant que vous touchez chaque contrôle d'une source (Synthtribe, Reaktor, etc.).

    Setup type :
        Synthtribe → loopMIDI virtuel → ce sniffer → TD-3 (optionnel)

    Limites : Synthtribe ne transmet pas vraiment de CC pour le timbre.
    Utiliser plutôt `td3 probe` pour piloter activement la TD-3 et écouter.
    """
    _require_mido()
    from .sniff import run_sniffer, summarise
    captures = run_sniffer(port, timeout_s=timeout, out_path=out_path)
    summarise(captures)


@main.command()
@click.option("--port", required=True, help="Port MIDI d'entrée à écouter (port loopback virtuel par ex.).")
@click.option("--forward-to", default=None, help="Port MIDI de sortie où relayer chaque message reçu (passthrough).")
@click.option("--clock", is_flag=True, default=False, help="Afficher aussi les Timing Clock (sinon filtrés).")
def monitor(port: str, forward_to: str | None, clock: bool) -> None:
    """Moniteur passif : affiche tout ce qui arrive sur un port MIDI, avec timestamps.

    Setup typique sur Windows pour sniffer Synthtribe :
        1. loopMIDI (gratuit) → créer un port virtuel "TD-3-Sniff"
        2. Synthtribe → MIDI Out = "TD-3-Sniff"
        3. td3 monitor --port "TD-3-Sniff" --forward-to "TD-3 MIDI 1"
        4. Tout ce que Synthtribe envoie est affiché ET relayé à la TD-3.
    """
    _require_mido()
    from .sniff import run_monitor
    run_monitor(port, forward_to=forward_to, show_clock=clock)


@main.command()
@click.option("--port", required=True, help="Port MIDI de sortie vers la TD-3.")
@click.option("--channel", default=1, show_default=True, help="Canal MIDI (1..16).")
@click.option("--start", default=0, show_default=True, help="Premier numéro de CC à tester.")
@click.option("--end",   default=127, show_default=True, help="Dernier numéro de CC à tester.")
@click.option("--out", "out_path", type=click.Path(dir_okay=False, path_type=Path),
              default=Path("td3_cc_discovered.json"), show_default=True)
def probe(port: str, channel: int, start: int, end: int, out_path: Path) -> None:
    """Active probe : envoie CC 0..127 sur la TD-3 et vous demande après chaque envoi si vous entendez un changement.

    Conseil : maintenir une note ou lancer une pattern simple sur la TD-3
    pour mieux entendre l'effet de chaque CC.
    """
    _require_mido()
    from .sniff import run_active_probe
    run_active_probe(port, cc_range=(start, end), channel=channel, out_path=out_path)


@main.command(name="send-all")
@click.argument("yaml_dir", type=click.Path(exists=True, file_okay=False, path_type=Path))
@click.option("--port", required=True)
def send_all(yaml_dir: Path, port: str) -> None:
    """Envoie tous les patterns YAML d'un dossier vers la TD-3."""
    mido = _require_mido()
    target = _resolve_port(mido.get_output_names(), port)
    files = _sorted_pattern_files(Path(yaml_dir))
    with mido.open_output(target) as out:
        for f in files:
            p = pattern_from_yaml(f.read_text())
            out.send(mido.Message.from_bytes(pattern_to_sysex(p)))
    click.echo(f"sent {len(files)} patterns to {target!r}")


def _resolve_port(available: list[str], wanted: str) -> str:
    if wanted in available:
        return wanted
    matches = [n for n in available if wanted.lower() in n.lower()]
    if len(matches) == 1:
        return matches[0]
    if not matches:
        raise click.ClickException(
            f"no MIDI port matches {wanted!r}. Available: {available}"
        )
    raise click.ClickException(f"ambiguous port {wanted!r}: {matches}")


if __name__ == "__main__":
    main()
