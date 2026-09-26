import argparse
import json
import os
from pathlib import Path
from .store import Store


def main():
    parser = argparse.ArgumentParser(description='Local-first Turbo IO API, no device I/O')
    parser.add_argument('--db', type=Path, default=Path('.state/turboio.sqlite3'))
    commands = parser.add_subparsers(dest='command', required=True)
    grant = commands.add_parser('grant', help='Issue device-scoped token into a NEW local file')
    grant.add_argument('--role', choices=['writer', 'reader', 'phone'], required=True)
    grant.add_argument('--device', required=True)
    grant.add_argument('--out', type=Path, required=True)
    serve = commands.add_parser('serve')
    serve.add_argument('--port', type=int, default=18796)
    args = parser.parse_args()
    store = Store(args.db)
    if args.command == 'grant':
        fd = os.open(args.out, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, 'w') as stream:
            stream.write(store.issue(args.role, args.device)+'\n')
        print(json.dumps({'created': str(args.out), 'role': args.role, 'device': args.device}))
    else:
        import uvicorn
        from .server import create_app
        # No public listen flag. Operators must explicitly configure TLS reverse proxy.
        uvicorn.run(create_app(store), host='127.0.0.1', port=args.port, access_log=False)


if __name__ == '__main__':
    main()
