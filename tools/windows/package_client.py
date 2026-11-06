"""Assemble a local PKA Windows distribution from explicit source/artifact trees.

Only Git-listed runtime sources are copied. Private assets stay local; account
settings, captures, keys and logs are never pulled from the Android workspace.
The private pre-auth file must be supplied explicitly for this local installation.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path


def sha(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--binary', type=Path, required=True)
    parser.add_argument('--assets', type=Path, required=True)
    parser.add_argument('--images', type=Path, required=True)
    parser.add_argument('--preauth', type=Path, required=True, help='Private local PKA pre-auth file; never commit it')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError('Use a new output directory to preserve existing profiles')
    preauth = args.preauth.read_bytes()
    fields = preauth.decode('utf-8').split('\n')
    if len(fields) != 4 or any(not field or '\r' in field for field in fields):
        raise ValueError('Pre-auth must contain exactly four non-empty LF-separated fields without a trailing newline')
    required = ['things.dat', 'things.spr', 'things.otfi', 'things.otml']
    for name in required:
        path = args.assets / 'data/things' / name
        with path.open('rb') as stream:
            if stream.read(4) in (b'PKA1', b'PKB1'):
                raise ValueError(f'Assets must already be authenticated and extracted: {name}')
    executable = args.binary / 'otclient.exe'
    if not executable.is_file():
        raise FileNotFoundError(executable)
    args.output.mkdir(parents=True)
    (args.output / 'pokealliance-preauth.txt').write_bytes(preauth)
    files = subprocess.check_output(['git', '-C', str(args.source), 'ls-files', '-z']).decode().split('\0')
    roots = ('data/', 'modules/', 'mods/')
    root_files = {'init.lua', 'otclientrc.lua', 'config.ini', 'cacert.pem', 'LICENSE', 'LICENSE.txt'}
    for name in files:
        if name and (name.startswith(roots) or name in root_files):
            src = args.source / name
            if src.is_file():
                dst = args.output / name
                dst.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst)
    for src in args.binary.iterdir():
        if src.is_file() and (src.suffix.lower() in ('.exe', '.dll') or src.name == 'build-info.json'):
            shutil.copy2(src, args.output / src.name)
    for version in ('860', '1511'):
        dst = args.output / 'data/things' / version
        dst.mkdir(parents=True)
        for name in required:
            runtime_name = {'things.dat': 'Tibia.dat', 'things.spr': 'Tibia.spr'}.get(name, name)
            shutil.copy2(args.assets / 'data/things' / name, dst / runtime_name)
    for group in ('pokemons', 'conditions'):
        shutil.copytree(args.images / 'data/images' / group, args.output / 'data/images' / group, dirs_exist_ok=True)
    init = args.output / 'init.lua'
    text = init.read_text(encoding='utf-8')
    for before, after in (
        ('g_app.setName("OTClient - Redemption")', 'g_app.setName("PokeAlliance - Cliente Windows")'),
        ('g_app.setCompactName("otclient")', 'g_app.setCompactName("pka_windows")'),
    ):
        if text.count(before) != 1:
            raise ValueError(f'Unexpected init.lua: {before}')
        text = text.replace(before, after)
    init.write_text(text, encoding='utf-8')
    (args.output / 'Iniciar.cmd').write_text('@echo off\ncd /d "%~dp0"\nstart "" "%~dp0otclient.exe" --user-dir=profile\n', encoding='ascii')
    (args.output / 'LEIA-ME.txt').write_text(
        'Cliente PokeAlliance para Windows x64 - primeira versao de teste\n\n'
        'Abra Iniciar.cmd. O perfil local fica em profile. Login manual.\n'
        'Mouse/teclado usam os controles desktop do OTClient.\n'
        'Clique na Pokebar para selecionar; clique nas skills para usar.\n'
        'A janela Comandos oferece Ordenar Pokemon e controles de voo.\n'
        'Use as opcoes de controles/atalhos para personalizar o teclado.\n'
        'Bot: combo assistido manual; hunt autonoma ainda nao implementada.\n'
        'Compatibilidade com o servidor atualizado depende de teste real.\n', encoding='utf-8')
    manifest = {str(p.relative_to(args.output)).replace('\\', '/'): {'size': p.stat().st_size, 'sha256': sha(p)}
                for p in sorted(args.output.rglob('*')) if p.is_file()}
    (args.output / 'package-manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(f'Packaged {len(manifest)} files in {args.output}')


if __name__ == '__main__':
    main()
