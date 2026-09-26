import argparse
import json
from pathlib import Path
from .app_package import build_package, read_package


def main():
    parser = argparse.ArgumentParser(description='TAP1 draft host toolchain; not a glasses installer')
    cmd = parser.add_subparsers(dest='command', required=True)
    build = cmd.add_parser('build'); build.add_argument('source', type=Path); build.add_argument('--out', type=Path, required=True)
    check = cmd.add_parser('check'); check.add_argument('package', type=Path)
    preview = cmd.add_parser('preview'); preview.add_argument('package', type=Path); preview.add_argument('--page', required=True); preview.add_argument('--out', type=Path, required=True)
    gallery=cmd.add_parser('gallery',help='Offline MCP recipes and snapshot packages')
    sub=gallery.add_subparsers(dest='gallery_command',required=True)
    sub.add_parser('list')
    export=sub.add_parser('export');export.add_argument('--out',type=Path,required=True)
    prompt=sub.add_parser('prompt');prompt.add_argument('id')
    snapshot=sub.add_parser('build');snapshot.add_argument('id');snapshot.add_argument('--data',type=Path);snapshot.add_argument('--version',type=int,default=1);snapshot.add_argument('--out',type=Path,required=True)
    args = parser.parse_args()
    if args.command=='gallery':
        from .gallery import cli
        return cli(args)
    if args.command == 'build':
        with args.source.open('rb') as stream:
            raw = stream.read(20_481)
        data = build_package(json.loads(raw))
        with args.out.open('xb') as stream:
            stream.write(data)
    else:
        with args.package.open('rb') as stream:
            data = stream.read(24_577)
    result = read_package(data)
    if args.command == 'preview':
        from .preview import render
        with args.out.open('x') as stream:
            stream.write(render(result['document'], args.page))
    print(json.dumps({k: v for k, v in result.items() if k != 'document'}, ensure_ascii=False))


if __name__ == '__main__':
    main()
