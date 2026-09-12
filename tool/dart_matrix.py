"""Discover every published Dart 3.x stable patch from 3.10.0 onward."""
import json, os, re, urllib.parse, urllib.request

def discover():
    latest = json.load(urllib.request.urlopen(
        'https://storage.googleapis.com/dart-archive/channels/stable/release/latest/VERSION'))['version']
    upper = tuple(map(int, latest.split('.')))
    versions = set()
    token = None
    while True:
        query = {'prefix': 'channels/stable/release/3.', 'delimiter': '/'}
        if token:
            query['pageToken'] = token
        url = 'https://storage.googleapis.com/storage/v1/b/dart-archive/o?' + urllib.parse.urlencode(query)
        page = json.load(urllib.request.urlopen(url))
        for prefix in page.get('prefixes', []):
            version = prefix.rstrip('/').split('/')[-1]
            if re.fullmatch(r'3\.\d+\.\d+', version):
                number = tuple(map(int, version.split('.')))
                if (3, 10, 0) <= number <= upper:
                    versions.add(version)
        token = page.get('nextPageToken')
        if not token:
            break
    versions = sorted(versions, key=lambda v: tuple(map(int, v.split('.'))))
    if not versions or versions[0] != '3.10.0':
        raise RuntimeError('Minimum supported SDK is missing from official archive')
    if upper[0] != 3:
        raise RuntimeError('A new Dart major requires an explicit support decision')
    if latest not in versions or len(versions) * 2 > 256:
        raise RuntimeError('Incomplete archive or GitHub matrix capacity exceeded')
    return versions, latest

if __name__ == '__main__':
    versions, latest = discover()
    result = json.dumps(versions)
    print(result)
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf8') as out:
            out.write(f'sdks={result}\nlatest={latest}\n')
