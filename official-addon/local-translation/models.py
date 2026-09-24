"""Explicit opt-in downloads of pinned public weights; never uses API keys.
Model licenses are independent of the original integration code's license.
"""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE/'src'))
from prepare_hymt_model import prepare

def sha(path):
    h = hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda: f.read(1024*1024), b''): h.update(b)
    return h.hexdigest()

def verify(directory):
    hy = json.loads((HERE/'hymt-manifest.json').read_text())
    model = directory/'Hy-MT2-1.8B-STQ43.gguf'
    if model.stat().st_size != hy['size_bytes'] or sha(model) != hy['adapted_sha256']:
        raise ValueError('Hy-MT integrity mismatch')
    manifest = json.loads((HERE/'parakeet-manifest.json').read_text())
    actual = json.loads((directory/'ParakeetEOU320/manifest.json').read_text())
    if actual != manifest: raise ValueError('Parakeet manifest mismatch')
    for entry in manifest['files']:
        file = directory/'ParakeetEOU320'/entry['path']
        if file.is_symlink() or file.stat().st_size != entry['size'] or sha(file) != entry['sha256']:
            raise ValueError('Parakeet integrity mismatch')
    return True

def download(url, path, size, digest):
    if path.exists(): raise ValueError('Refuse to overwrite model')
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(path.name+'.download')
    if partial.exists(): raise ValueError('Partial exists; inspect it and use a new output path')
    subprocess.run(['curl','--proto','=https','--proto-redir','=https','-fL','--retry','3',
                    '--max-time','1200','-o',str(partial),url], check=True)
    if partial.stat().st_size != size or sha(partial) != digest:
        raise ValueError('Download integrity mismatch; kept partial for inspection')
    partial.rename(path)

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--out', type=Path, required=True)
    p.add_argument('--accept-model-licenses', action='store_true')
    p.add_argument('--verify-only', action='store_true')
    a = p.parse_args(); out = a.out.resolve()
    if a.verify_only:
        verify(out); print('Pinned model files verified'); return
    if not a.accept_model_licenses: p.error('Read THIRD_PARTY.md and pass --accept-model-licenses to download')
    if out.exists(): p.error('Use a new output directory')
    out.mkdir(parents=True)
    hy = json.loads((HERE/'hymt-manifest.json').read_text())
    original = out/hy['original_file']
    download(hy['model_repository']+'/resolve/'+hy['model_revision']+'/'+hy['original_file'], original,
             hy['size_bytes'], hy['original_sha256'])
    prepare(original, out/'Hy-MT2-1.8B-STQ43.gguf')
    manifest = json.loads((HERE/'parakeet-manifest.json').read_text())
    for e in manifest['files']:
        rel = urllib.parse.quote('320ms/'+e['path'], safe='/')
        download('https://huggingface.co/'+manifest['repo']+'/resolve/'+manifest['revision']+'/'+rel,
                 out/'ParakeetEOU320'/e['path'], e['size'], e['sha256'])
    shutil.copyfile(HERE/'parakeet-manifest.json',out/'ParakeetEOU320/manifest.json')
    verify(out); print('Public models prepared; original preserved. No runtime or device operation.')

if __name__ == '__main__':
    main()
