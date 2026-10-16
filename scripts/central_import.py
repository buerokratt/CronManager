"""Original DataMapper fields, deterministic IDs, bounded authenticated import."""
import argparse
import base64
import fcntl
import hashlib
import json
import os
from pathlib import Path
import ssl
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import Request, ProxyHandler, HTTPSHandler, HTTPRedirectHandler, build_opener


class ImportStopped(Exception):
    pass


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise ImportStopped('redirect_refused')


def origin(value):
    parsed = urlsplit(value)
    if parsed.scheme not in ('https', 'http') or not parsed.hostname or parsed.username or parsed.password or parsed.path not in ('', '/') or parsed.query or parsed.fragment:
        raise ImportStopped('invalid_origin')
    if parsed.scheme == 'http' and os.getenv('CENTRAL_IMPORT_ALLOW_HTTP') != 'true':
        raise ImportStopped('http_not_explicitly_enabled')
    return value.rstrip('/')


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def document_id(dataset, doc):
    keys = ('registry_code',) if dataset == 'companies' else ('month', 'county', 'local_government', 'field_of_activity')
    values = [doc.get(key) for key in keys]
    if any(not isinstance(value, str) or not value.strip() for value in values):
        raise ImportStopped('missing_stable_identity_fields')
    return dataset + '-' + hashlib.sha256(canonical(values)).hexdigest()


def atomic_json(path, value):
    temporary = path.with_suffix('.tmp')
    with temporary.open('w') as file:
        json.dump(value, file, sort_keys=True); file.flush(); os.fsync(file.fileno())
    os.replace(temporary, path)
    descriptor = os.open(path.parent, os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dataset', choices=('companies', 'municipalities'), required=True)
    args = parser.parse_args()
    dataset = args.dataset
    endpoint = origin(os.environ['CENTRAL_OPENSEARCH_URL'])
    mapper = origin(os.environ['CENTRAL_DATA_MAPPER_URL'])
    prefix = os.environ['CENTRAL_INDEX_PREFIX']
    if prefix != 'central-byk-test-common-':
        raise ImportStopped('installation_prefix_mismatch')
    index = prefix + dataset
    username = Path(os.environ['CENTRAL_OS_USERNAME_FILE']).read_text()
    password = Path(os.environ['CENTRAL_OS_PASSWORD_FILE']).read_text()
    if not username or not password or ':' in username or any(ord(c) < 32 for c in username + password):
        raise ImportStopped('invalid_credential_files')
    auth = 'Basic ' + base64.b64encode((username + ':' + password).encode()).decode()
    opener = build_opener(ProxyHandler({}), NoRedirect(), HTTPSHandler(context=ssl.create_default_context(cafile=os.getenv('CENTRAL_OS_CA_FILE') or None)))

    def request(method, url, body=None, kind='application/json', authenticated=False):
        headers = {'Content-Type': kind}
        if authenticated:
            headers['Authorization'] = auth
        data = body if isinstance(body, bytes) else None if body is None else canonical(body)
        try:
            with opener.open(Request(url, method=method, data=data, headers=headers), timeout=30) as response:
                raw = response.read(32 * 1024 * 1024 + 1)
                if len(raw) > 32 * 1024 * 1024:
                    raise ImportStopped('response_limit')
                return raw
        except HTTPError as error:
            code = error.code; error.close()
            raise ImportStopped('http_' + str(code)) from None
        except (OSError, ValueError):
            raise ImportStopped('transport_or_json_failure') from None

    root = Path(os.getenv('CENTRAL_IMPORT_ROOT', '/app/services')).resolve(strict=True)
    pending = root / dataset / 'unprocessed'; processed = root / dataset / 'processed'
    processed.mkdir(parents=True, exist_ok=True)
    journal = Path(os.getenv('CENTRAL_IMPORT_JOURNAL', '/app/import-journal'))
    journal.mkdir(parents=True, exist_ok=True)
    with (journal / (dataset + '.lock')).open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        for file in sorted(pending.glob('*.csv')):
            if file.is_symlink() or file.resolve().parent != pending.resolve():
                raise ImportStopped('input_path_boundary')
            if file.stat().st_size > 16 * 1024 * 1024:
                raise ImportStopped('input_limit')
            source_hash = hashlib.sha256(file.read_bytes()).hexdigest()
            mapper_path = os.getenv('CENTRAL_MAPPER_IMPORT_ROOT', '/OpenSearch/services').rstrip('/') + '/' + dataset + '/unprocessed/' + file.name
            mapped = request('POST', mapper + '/parse-csv-to-opensearch-data', {'file_path': mapper_path, 'csv_type': dataset}).decode().splitlines()
            if not mapped or len(mapped) % 2:
                raise ImportStopped('invalid_mapper_bulk')
            documents = []
            for offset in range(0, len(mapped), 2):
                action = json.loads(mapped[offset]); doc = json.loads(mapped[offset + 1])
                if set(action) != {'index'} or not isinstance(action['index'], dict) or not isinstance(doc, dict):
                    raise ImportStopped('invalid_mapper_action')
                documents.append((document_id(dataset, doc), doc))
            if len({identifier for identifier, _ in documents}) != len(documents):
                raise ImportStopped('duplicate_dataset_identity')
            entry_path = journal / (dataset + '-' + source_hash + '.json')
            previous = json.loads(entry_path.read_text()) if entry_path.exists() else None
            expected = {'dataset': dataset, 'sourceSHA256': source_hash, 'index': index,
                        'documents': [{'id': key, 'sha256': hashlib.sha256(canonical(doc)).hexdigest()} for key, doc in documents]}
            if previous and any(previous.get(key) != value for key, value in expected.items()):
                raise ImportStopped('journal_contract_conflict')
            # A prior ambiguous transport or partial write is reconciled by exact
            # realtime reads, never replayed blindly. IDs and source fields match.
            if previous:
                found = json.loads(request('POST', endpoint + '/' + index + '/_mget', {'ids': [key for key, _ in documents]}, authenticated=True))
                matched = all(item.get('found') and item.get('_id') == key and canonical(item.get('_source')) == canonical(doc)
                              for item, (key, doc) in zip(found.get('docs', []), documents)) and len(found.get('docs', [])) == len(documents)
                if not matched:
                    raise ImportStopped('prior_write_requires_explicit_reconciliation')
                expected['state'] = 'confirmed'
            else:
                expected['state'] = 'pending'
                atomic_json(entry_path, expected)
                # One bounded request; no SDK retry or recursive batch replay.
                body = b''.join(canonical({'index': {'_index': index, '_id': key}}) + b'\n' + canonical(doc) + b'\n' for key, doc in documents)
                if len(body) > 16 * 1024 * 1024:
                    raise ImportStopped('batch_limit')
                result = json.loads(request('POST', endpoint + '/' + index + '/_bulk', body, 'application/x-ndjson', authenticated=True))
                items = result.get('items', [])
                if result.get('errors') is not False or len(items) != len(documents) or any(not isinstance(item, dict) or set(item) != {'index'} or not isinstance(item.get('index'), dict) or type(item['index'].get('status')) is not int or not 200 <= item['index']['status'] < 300 or item['index'].get('error') or item['index'].get('_id') != identifier or item['index'].get('_index') != index for item, (identifier, _) in zip(items, documents)):
                    expected['state'] = 'partial_or_failed'; atomic_json(entry_path, expected)
                    raise ImportStopped('bulk_item_failure')
                expected['state'] = 'confirmed'
            atomic_json(entry_path, expected)
            if hashlib.sha256(file.read_bytes()).hexdigest() != source_hash:
                raise ImportStopped('input_changed_during_import')
            destination = processed / file.name
            if destination.exists():
                raise ImportStopped('processed_filename_collision')
            file.rename(destination)
            print(json.dumps({'dataset': dataset, 'sourceSHA256': source_hash, 'documents': len(documents), 'state': 'confirmed'}))


if __name__ == '__main__':
    try:
        main()
    except ImportStopped as error:
        print('Import stopped:', str(error)); raise SystemExit(1)
    except Exception as error:
        print('Import stopped:', type(error).__name__); raise SystemExit(1)
