#!/usr/bin/env python3
"""Loopback-only Watch server. Native libraries are read only."""
import argparse
import json
import os
from pathlib import Path
import subprocess
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = Path(__file__).resolve().parent
NATIVE = Path.home() / 'Library/Application Support/Watch'


def read(path, default):
    return json.loads(path.read_text()) if path.exists() else default


def initial_state():
    library = read(NATIVE / 'bookmarkLibrary.json', {})
    return dict(bookmarks=library.get('bookmarks', []),
                removedKeys=library.get('removedKeys', []),
                sectionKeys=library.get('sectionKeys', {}),
                favourites=read(NATIVE / 'favourites.json', {'entries': {}})['entries'],
                progress={})


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, data, content_type='application/json'):
        body = json.dumps(data).encode() if content_type == 'application/json' else data
        self.send_response(code)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Referrer-Policy', 'strict-origin-when-cross-origin')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.end_headers()
        self.wfile.write(body)

    def allowed(self, write=False):
        # Reject DNS rebinding and cross-site requests, including simple POSTs.
        origin = f'http://127.0.0.1:{self.server.server_port}'
        return (self.headers.get('Host') == origin[7:] and
                (not write or (self.headers.get('Origin') == origin and
                 self.headers.get('Content-Type') == 'application/json')))

    def do_GET(self):
        if not self.allowed():
            return self.reply(403, {'error': 'Use the printed localhost address.'})
        if self.path == '/api/library':
            return self.reply(200, self.server.state)
        assets = {'/': ('index.html', 'text/html; charset=utf-8'),
                  '/app.js': ('app.js', 'text/javascript'),
                  '/style.css': ('style.css', 'text/css')}
        if self.path not in assets:
            return self.reply(404, {'error': 'Not found'})
        name, mime = assets[self.path]
        self.reply(200, (ROOT / 'dist' / name).read_bytes(), mime)

    def do_POST(self):
        if not self.allowed(write=True):
            return self.reply(403, {'error': 'Request origin rejected.'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 4096:
                raise ValueError('Invalid request size')
            action = json.loads(self.rfile.read(length))
            state = json.loads(json.dumps(self.server.state))
            if self.path == '/api/refresh':
                result = subprocess.run([str(self.server.exporter)], capture_output=True, text=True, timeout=30)
                if result.returncode:
                    raise ValueError(result.stderr.strip() or 'Firefox refresh failed')
                state['bookmarks'] = json.loads(result.stdout)
            elif self.path == '/api/change':
                key, kind = action['key'], action['kind']
                if not isinstance(key, str) or len(key) > 2048:
                    raise ValueError('Invalid key')
                if kind in ('removed', 'sleep', 'eat'):
                    if type(action['enabled']) is not bool:
                        raise ValueError('Invalid selection')
                    values = set(state['removedKeys'] if kind == 'removed' else state['sectionKeys'].get(kind, []))
                    values.add(key) if action['enabled'] else values.discard(key)
                    if kind == 'removed':
                        state['removedKeys'] = sorted(values)
                    else:
                        state['sectionKeys'][kind] = sorted(values)
                elif kind == 'favourite':
                    if key in state['favourites']:
                        del state['favourites'][key]
                    else:
                        story = next(s for s in state['bookmarks'] if s['id'] == action['id'])
                        import time
                        state['favourites'][key] = {'story': story, 'savedAt': time.time() - 978307200}
                elif kind == 'progress':
                    seconds = action['seconds']
                    if not isinstance(seconds, (int, float)) or not 0 <= seconds < 1e8:
                        raise ValueError('Invalid playback position')
                    state['progress'][key] = seconds
                else:
                    raise ValueError('Unknown change')
            else:
                return self.reply(404, {'error': 'Not found'})
            self.server.state_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
            temporary = self.server.state_path.with_suffix('.tmp')
            temporary.write_text(json.dumps(state))
            os.chmod(temporary, 0o600)
            temporary.replace(self.server.state_path)
            self.server.state = state
            self.reply(200, state)
        except (ValueError, KeyError, StopIteration, OSError, subprocess.TimeoutExpired) as error:
            self.reply(400, {'error': str(error) or 'Invalid request'})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8765)
    parser.add_argument('--state', type=Path, default=ROOT / '.local/library.json')
    parser.add_argument('--exporter', type=Path, default=ROOT.parent / '.build/debug/WatchExport')
    args = parser.parse_args()
    server = HTTPServer(('127.0.0.1', args.port), Handler)
    server.state_path = args.state
    server.exporter = args.exporter
    server.state = read(args.state, None)
    if server.state is None:
        server.state = initial_state()
    print(f'Watch is ready at http://127.0.0.1:{args.port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
