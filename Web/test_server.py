import http.client
import json
from pathlib import Path
import tempfile
import threading
import unittest
from http.server import HTTPServer
from server import Handler


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.server = HTTPServer(('127.0.0.1', 0), Handler)
        self.server.state_path = Path(self.temp.name) / 'library.json'
        self.server.state = {'bookmarks': [{'id': 'one', 'title': 'Example'}], 'favourites': {}, 'removedKeys': [], 'sectionKeys': {}, 'progress': {}}
        self.thread = threading.Thread(target=self.server.serve_forever)
        self.thread.start()
        self.origin = f'http://127.0.0.1:{self.server.server_port}'

    def tearDown(self):
        self.server.shutdown()
        self.thread.join()
        self.server.server_close()
        self.temp.cleanup()

    def request(self, path, body=None, origin=None, host=None):
        connection = http.client.HTTPConnection('127.0.0.1', self.server.server_port)
        headers = {'Content-Type': 'application/json', 'Origin': origin or self.origin}
        if host:
            headers['Host'] = host
        connection.request('POST' if body is not None else 'GET', path, json.dumps(body) if body is not None else None, headers)
        response = connection.getresponse()
        result = response.status, response.read()
        connection.close()
        return result

    def test_changes_persist_and_restore(self):
        for enabled in (True, False):
            status, _ = self.request('/api/change', {'kind': 'removed', 'key': 'youtube:abc', 'enabled': enabled})
            self.assertEqual(status, 200)
            self.assertEqual('youtube:abc' in json.loads(self.server.state_path.read_text())['removedKeys'], enabled)
        self.request('/api/change', {'kind':'sleep', 'key':'youtube:abc', 'enabled':True})
        self.request('/api/change', {'kind':'favourite', 'key':'youtube:abc', 'id':'one'})
        self.request('/api/change', {'kind':'progress', 'key':'youtube:abc', 'seconds':123})
        saved = json.loads(self.server.state_path.read_text())
        self.assertEqual(saved['sectionKeys']['sleep'], ['youtube:abc'])
        self.assertEqual(saved['favourites']['youtube:abc']['story']['title'], 'Example')
        self.assertEqual(saved['progress']['youtube:abc'], 123)

    def test_cross_origin_and_rebinding_rejected(self):
        body = {'kind':'removed', 'key':'a', 'enabled':True}
        self.assertEqual(self.request('/api/change', body, origin='https://example.com')[0], 403)
        self.assertEqual(self.request('/api/library', host='example.com')[0], 403)
        self.assertFalse(self.server.state_path.exists())

    def test_invalid_progress_does_not_write(self):
        self.assertEqual(self.request('/api/change', {'kind':'progress', 'key':'a', 'seconds':-1})[0], 400)
        self.assertFalse(self.server.state_path.exists())

    def test_static_routes_do_not_expose_files(self):
        self.assertEqual(self.request('/../server.py')[0], 404)
        status, _ = self.request('/')
        self.assertEqual(status, 200)


if __name__ == '__main__':
    unittest.main()
