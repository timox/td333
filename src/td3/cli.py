"""CLI: simplify writing TD-3 MIDI patterns from YAML."""
from __future__ import annotations

import os
import sys
from pathlib import Path

import click

from .pattern import Pattern
from .sqs import SQSFile, read_sqs, write_sqs
from .sysex import iter_sysex, pattern_to_sysex, request_pattern, sysex_to_pattern
from .yaml_io import _GROUP_LABELS, format_pattern_label, pattern_from_yaml, pattern_to_yaml


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
