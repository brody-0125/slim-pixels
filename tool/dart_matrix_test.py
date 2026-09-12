"""Offline check of paging, stable filtering and fail-closed discovery."""
import io, json, unittest
from unittest.mock import patch
from dart_matrix import discover

class MatrixTest(unittest.TestCase):
    def test_pages_and_filter(self):
        pages = [
            {'version': '3.11.2'},
            {'prefixes': [f'channels/stable/release/{v}/' for v in ['3.9.9','3.10.0','3.11.0-beta']], 'nextPageToken':'next'},
            {'prefixes': [f'channels/stable/release/{v}/' for v in ['3.11.2','3.10.9','3.11.3']]},
        ]
        with patch('urllib.request.urlopen', side_effect=[io.BytesIO(json.dumps(p).encode()) for p in pages]):
            self.assertEqual(discover(), (['3.10.0','3.10.9','3.11.2'], '3.11.2'))
    def test_missing_minimum_fails(self):
        with patch('urllib.request.urlopen', side_effect=[io.BytesIO(b'{"version":"3.13.3"}'),io.BytesIO(b'{"prefixes":[]}')]):
            with self.assertRaises(RuntimeError):discover()

if __name__ == '__main__':unittest.main()
