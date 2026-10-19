#!/usr/bin/env python3
"""Read-only full-demo acceptance checks after deployment and Private Link approval."""
import argparse
import json
import time
import uuid
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def get(url):
    try:
        response = urllib.request.urlopen(url, timeout=45)
    except urllib.error.HTTPError as error:
        response = error
    with response:
        return response.status, response.headers, response.read()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base_url')
    parser.add_argument('--function-host', required=True)
    parser.add_argument('--webapp-host', required=True)
    parser.add_argument('--storage-account', action='append', required=True)
    args = parser.parse_args()
    if not args.base_url.startswith('https://'):
        parser.error('Use an HTTPS Front Door URL.')
    base = args.base_url.rstrip('/')
    report = []
    run = uuid.uuid4().hex

    def record(name, **data):
        item = {'check': name, **data}
        report.append(item)
        print(json.dumps(item), flush=True)

    for path, expected_type in [('/', 'text/html'), ('/logos/demo', 'text/html'),
                                ('/logos/health', 'text/plain')]:
        status, headers, body = get(base + path)
        assert status == 200, (path, status, body[:200])
        assert headers.get_content_type() == expected_type, (path, dict(headers))
        assert headers.get('Cache-Control') == 'no-store', (path, dict(headers))
        if path == '/':
            assert headers.get('X-Demo-Origin') == 'webapp', dict(headers)
        record(path, status=status)

    cases = [
        ('/logos/ACME.svg', 200, 'original', 'ACME.svg'),
        ('/logos/CONTOSO.svg', 200, 'original', 'CONTOSO.svg'),
        ('/logos/JEMXX.svg', 200, 'fallback', None),
        ('/logos/JEMXX.svg?explicit=true', 404, 'explicit-not-found', None),
        ('/logos/ACME.svg?explicit=true', 200, 'original', 'ACME.svg'),
        ('/logos/fallback/JEMXX.svg', 200, 'fallback', None),
        ('/static/v2/static/logos/JEMXX.svg', 200, 'fallback', None),
    ]
    # Repeat both query variants to catch cache contamination in either direction.
    for iteration in range(2):
        for path, expected_status, result, fixture in cases:
            url = base + path + ('&' if '?' in path else '?') + 'acceptance=' + run
            status, headers, body = get(url)
            assert status == expected_status, (path, status, body[:200])
            assert headers.get('X-Logo-Result') == result, (path, dict(headers))
            if status == 404:
                assert headers.get('Cache-Control') == 'no-store', dict(headers)
                assert 'HIT' not in headers.get('X-Cache', ''), dict(headers)
            else:
                assert headers.get_content_type() == 'image/svg+xml', dict(headers)
                svg = ET.fromstring(body)
                if fixture:
                    assert body == (ROOT / 'assets/logos' / fixture).read_bytes(), path
                else:
                    assert svg.find('{http://www.w3.org/2000/svg}text').text == 'JE', path
            record(path, iteration=iteration + 1, status=status, result=result,
                   cache=headers.get('X-Cache'), age=headers.get('Age'))

    for symbol, result in [('ACME', 'original'), ('JEMXX', 'fallback')]:
        url = base + '/logos/' + symbol + '.svg?cachecheck=' + run
        for attempt in range(20):
            status, headers, body = get(url)
            assert status == 200 and headers.get('X-Logo-Result') == result, (status, dict(headers))
            if 'HIT' in headers.get('X-Cache', ''):
                record('cache-hit-' + result, cache=headers['X-Cache'], age=headers.get('Age'))
                break
            time.sleep(2)
        else:
            raise AssertionError('No Front Door cache hit observed for ' + symbol)

    direct = [('function', args.function_host, '/logos/health'),
              ('webapp', args.webapp_host, '/')]
    direct += [('storage-' + account, account + '.blob.core.windows.net', '/?comp=list')
               for account in args.storage_account]
    for name, host, path in direct:
        status, headers, body = get('https://' + host + path)
        assert status == 403, (name, status, body[:200])
        record('direct-public-' + name, status=status)
    print(json.dumps({'result': 'PASS', 'checks': len(report)}), flush=True)


if __name__ == '__main__':
    main()
