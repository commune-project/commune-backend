#!/usr/bin/env python3
"""Owned temporary PostgreSQL + real Commune/TLS/SMTP acceptance. No external peers."""
import base64
import argparse
import email.utils
import hashlib
import http.client
import http.server
import json
import os
from pathlib import Path
import re
import shutil
import socket
import socketserver
import ssl
import subprocess
import tempfile
import threading
import time
import urllib.parse


def check(value, message):
    if not value:
        raise AssertionError(message)


def port():
    with socket.socket() as s:
        s.bind(('127.0.0.1', 0))
        return s.getsockname()[1]


def run(args, **kwargs):
    result = subprocess.run(args, capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise RuntimeError(f'{args[0]} failed: {result.stderr.strip()} {result.stdout.strip()}')
    return result.stdout.strip()


def eventually(fn, label, timeout=25):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = fn()
        if value:
            return value
        time.sleep(.2)
    raise AssertionError('timed out: ' + label)


class Mail(socketserver.StreamRequestHandler):
    def handle(self):
        self.wfile.write(b'220 localhost acceptance\r\n')
        recipient = ''
        while line := self.rfile.readline():
            verb = line.upper()
            if verb.startswith(b'EHLO'):
                self.wfile.write(b'250-localhost\r\n250 8BITMIME\r\n')
            elif verb.startswith(b'RCPT'):
                recipient = line.decode().strip()
                self.wfile.write(b'250 ok\r\n')
            elif verb.startswith(b'DATA'):
                self.wfile.write(b'354 continue\r\n')
                body = b''
                while (part := self.rfile.readline()) != b'.\r\n':
                    if not part:
                        return
                    body += part
                self.server.messages.append((recipient, body.decode()))
                self.wfile.write(b'250 stored\r\n')
            elif verb.startswith(b'QUIT'):
                self.wfile.write(b'221 bye\r\n')
                return
            else:
                self.wfile.write(b'250 ok\r\n')


class Proxy(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def do_GET(self):
        self.forward()

    do_HEAD = do_GET
    do_POST = do_GET
    do_PATCH = do_GET
    do_PUT = do_GET
    do_DELETE = do_GET

    def log_message(self, *args):
        pass

    def forward(self):
        body = self.rfile.read(int(self.headers.get('Content-Length', 0)))
        headers = dict(self.headers)
        headers['Connection'] = 'close'
        conn = http.client.HTTPConnection('127.0.0.1', self.server.backend, timeout=20)
        try:
            conn.request(self.command, self.path, body, headers)
            result = conn.getresponse()
            data = result.read()
            self.server.requests.append((self.command, self.path, result.status))
            self.send_response(result.status)
            for key, value in result.getheaders():
                if key.lower() not in ('connection', 'transfer-encoding', 'content-length'):
                    self.send_header(key, value)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            if self.command != 'HEAD':
                self.wfile.write(data)
        except (ConnectionError, TimeoutError):
            self.send_response(503)
            self.send_header('Content-Length', '0')
            self.end_headers()
        finally:
            conn.close()


class Client:
    def __init__(self, origin, context):
        self.origin, self.context = origin, context
        self.cookies = {}

    def request(self, method, path, data=None, expected=200, headers=None):
        hdr = {'Origin': self.origin, **(headers or {})}
        if self.cookies:
            hdr['Cookie'] = '; '.join(k + '=' + v for k, v in self.cookies.items())
            hdr['X-CSRF-Token'] = self.cookies.get('__Host-commune_csrf', '')
        if isinstance(data, dict):
            data = json.dumps(data).encode()
            hdr['Content-Type'] = 'application/json'
        conn = http.client.HTTPSConnection(urllib.parse.urlsplit(self.origin).netloc, context=self.context, timeout=20)
        try:
            conn.request(method, path, data, hdr)
            response = conn.getresponse()
            body = response.read()
            for key, value in response.getheaders():
                if key.lower() == 'set-cookie':
                    name, val = value.split(';', 1)[0].split('=', 1)
                    self.cookies[name] = val
            check(response.status in ([expected] if isinstance(expected, int) else expected),
                  f'{method} {path}: {response.status}, expected {expected}: {body[:300]!r}')
            content_type = response.getheader('Content-Type', '')
            return json.loads(body) if body and ('application/json' in content_type or '+json' in content_type) else body
        finally:
            conn.close()

    def upload(self, purpose='post'):
        # A decoded, valid 1x1 PNG; no image tooling or external asset fetch.
        png = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=')
        boundary = 'commune-acceptance-boundary'
        body = (f'--{boundary}\r\nContent-Disposition: form-data; name="purpose"\r\n\r\n{purpose}\r\n'
                f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="pixel.png"\r\nContent-Type: image/png\r\n\r\n').encode() + png + f'\r\n--{boundary}--\r\n'.encode()
        return self.request('POST', '/api/v1/media', body, 201, {'Content-Type': 'multipart/form-data; boundary=' + boundary})


class Acceptance:
    def __init__(self, root):
        self.root = Path(root)
        self.processes, self.servers, self.logs = [], [], []
        self.events = []
        self.binary = os.environ.get('COMMUNE_ACCEPTANCE_BINARY', '/tmp/commune-mygo-build/commune')
        self.pgport = port()

    def sql(self, db, query):
        return run(['psql', '-XAt', '-v', 'ON_ERROR_STOP=1', '-h', str(self.root / 'socket'), '-p', str(self.pgport), '-U', 'commune_test', '-d', db, '-c', query])

    @staticmethod
    def q(value):
        return "'" + str(value).replace("'", "''") + "'"

    def note(self, label):
        self.events.append(label)
        print('PASS ' + label, flush=True)

    def start(self):
        run(['initdb', '-D', str(self.root / 'pg'), '-A', 'trust', '-U', 'commune_test', '--no-locale', '-E', 'UTF8'])
        (self.root / 'socket').mkdir()
        run(['pg_ctl', '-D', str(self.root / 'pg'), '-l', str(self.root / 'pg.log'), '-o', f'-k {self.root}/socket -p {self.pgport} -h 127.0.0.1', '-w', 'start'])
        run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', str(self.root / 'tls.key'), '-out', str(self.root / 'tls.pem'), '-days', '1', '-subj', '/CN=localhost', '-addext', 'subjectAltName=IP:127.0.0.1,DNS:localhost'])
        self.context = ssl.create_default_context(cafile=str(self.root / 'tls.pem'))
        self.mail = socketserver.ThreadingTCPServer(('127.0.0.1', 0), Mail)
        self.mail.messages = []
        self.servers.append(self.mail)
        threading.Thread(target=self.mail.serve_forever, daemon=True).start()
        self.instances = {}
        for name in ('a', 'b'):
            self.sql('postgres', f'CREATE DATABASE {name}')
            backend, public = port(), port()
            origin = f'https://127.0.0.1:{public}'
            sites = [{'id': name, 'origin': origin, 'aliases': [], 'registration_enabled': True}]
            if name == 'a':
                sites.append({'id': 'c', 'origin': f'https://localhost:{public}', 'aliases': [], 'registration_enabled': True})
            config = {'sites': sites, 'database_url': f'postgres://commune_test@127.0.0.1:{self.pgport}/{name}?sslmode=disable', 'trusted_proxies': [],
                      'runtime': {'listen': f'127.0.0.1:{backend}', 'read_timeout_seconds': 15, 'write_timeout_seconds': 30, 'idle_timeout_seconds': 60, 'shutdown_timeout_seconds': 10, 'max_body_bytes': 2097152, 'max_page_size': 100, 'workers': 1},
                      'federation': {'allow_private_network': True, 'fetch_timeout_seconds': 10, 'max_fetch_bytes': 2097152, 'max_redirects': 3, 'clock_skew_seconds': 300},
                      'registration': {'outbox_secret': base64.b64encode(os.urandom(32)).decode()},
                      'smtp': {'host': '127.0.0.1', 'port': self.mail.server_address[1], 'from': 'acceptance@localhost', 'tls_mode': 'test', 'timeout_seconds': 3},
                      'media': {'enabled': True, 'root': str(self.root / ('media-' + name)), 'private_cache_retention_seconds': 60, 'cleanup_interval_seconds': 1},
                      'participation_workers': {'enabled': True, 'mail_workers': 1, 'notification_workers': 1, 'media_workers': 1, 'batch_size': 100, 'poll_interval_seconds': 1, 'lease_seconds': 15, 'retry_base_seconds': 1, 'retry_max_seconds': 5, 'max_attempts': 6}}
            path = self.root / (name + '.json')
            path.write_text(json.dumps(config))
            for command in ('check-config', 'migrate', 'provision-sites'):
                run([self.binary, command, str(path)])
            run([self.binary, 'provision-admin', str(path), name, 'admin'], env={**os.environ, 'COMMUNE_ADMIN_PASSWORD': 'acceptance-admin-password'})
            env = {**os.environ, 'SSL_CERT_FILE': str(self.root / 'tls.pem'), 'HTTPS_PROXY': '', 'HTTP_PROXY': '', 'ALL_PROXY': ''}
            log = open(self.root / (name + '.log'), 'w')
            self.logs.append(log)
            process = subprocess.Popen([self.binary, 'serve', str(path)], stdout=log, stderr=log, env=env)
            self.processes.append(process)
            proxy = http.server.ThreadingHTTPServer(('127.0.0.1', public), Proxy)
            proxy.backend, proxy.requests = backend, []
            tls = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            tls.load_cert_chain(str(self.root / 'tls.pem'), str(self.root / 'tls.key'))
            proxy.socket = tls.wrap_socket(proxy.socket, server_side=True)
            self.servers.append(proxy)
            threading.Thread(target=proxy.serve_forever, daemon=True).start()
            client = Client(origin, self.context)
            def ready():
                try:
                    client.request('GET', '/health/ready', expected=204)
                    return True
                except (OSError, AssertionError):
                    return False
            eventually(ready, name + ' readiness')
            client.request('POST', '/api/v1/auth/login', {'login': 'admin', 'password': 'acceptance-admin-password'})
            self.instances[name] = {'client': client, 'origin': origin, 'config': config, 'proxy': proxy}
        self.note('two independent Commune processes, isolated databases/media, trusted test TLS')

    def register(self, origin, username):
        client = Client(origin, self.context)
        email = username + '+' + urllib.parse.urlsplit(origin).netloc.replace(':', '-') + '@acceptance.invalid'
        client.request('POST', '/api/v1/auth/register', {'username': username, 'email': email}, 202)
        check(self.sql('a', "SELECT count(*) FROM accounts a JOIN sites s ON s.id=a.site_id WHERE a.username=" + self.q(username) + ' AND s.canonical_origin=' + self.q(origin)) == '0', 'registration created account before verification')
        message = eventually(lambda: next((body for recipient, body in self.mail.messages if email in recipient), None), 'verification SMTP')
        token = re.search(r'#token=([^\s<>]+)', message).group(1)
        client.request('POST', '/api/v1/auth/verification/confirm', {'token': token, 'password': 'acceptance-final-password'}, 204)
        identity = client.request('POST', '/api/v1/auth/login', {'login': username, 'password': 'acceptance-final-password'})
        return client, identity['actor_uri']

    def community(self, client, name, private=False, local=False):
        return client.request('POST', '/api/v1/communities', {'name': name, 'title': name, 'mode': 'local_only' if local else 'federated', 'read_policy': 'members' if private else 'eligible_users', 'post_policy': 'members' if private else 'eligible_users'}, 201)

    def local(self):
        a = self.instances['a']['client']
        origin = a.origin
        alice, self.alice = self.register(origin, 'alice')
        bob, self.bob = self.register(origin, 'bob')
        self.alice_client, self.bob_client = alice, bob
        self.note('9.3 registration: real SMTP, no pre-verification account, final password and login')
        replay = Client(self.instances['a']['config']['sites'][1]['origin'], self.context)
        replay.cookies = dict(alice.cookies)
        replay.request('GET', '/api/v1/auth/session', expected=401)
        replay.request('GET', '/api/v1/profiles/alice', expected=404)
        other, other_actor = self.register(replay.origin, 'alice')
        check(other_actor != self.alice, 'cross-site registration reused Actor identity')
        other.request('PATCH', '/api/v1/profile', {'display_name': 'Other-site Alice'})
        self.note('9.3 multi-site: cookie and public-profile isolation in shared deployment')
        avatar = alice.upload('avatar')
        alice.request('PATCH', '/api/v1/profile', {'display_name': '验收 Alice', 'biography': '**Hello** <script>alert(1)</script>', 'avatar_upload_id': avatar['id']})
        profile = alice.request('GET', '/api/v1/profile')
        check('验收' in json.dumps(profile, ensure_ascii=False), 'profile update absent')
        self.note('9.3 profile: avatar upload/binding and owner edit')
        group = self.community(alice, 'matrix', private=True)
        gid = group['id']
        alice.request('POST', f'/api/v1/communities/{gid}/members', {'actor': self.bob}, 204)
        upload = alice.upload()
        body = '中文验收 **rich** @bob\n\n![pixel](' + upload['reference'] + ')\n\n<script>alert(1)</script>'
        post = alice.request('POST', f'/api/v1/communities/{gid}/topics', {'title': '验收主题', 'body': body, 'content_format': 'markdown', 'attachment_ids': [upload['id']]}, 201)
        pid = post['id']
        check('<script' not in post['body_html'] and '<strong>rich</strong>' in post['body_html'], 'unsafe or missing rich output')
        source = alice.request('GET', f'/api/v1/posts/{pid}/source')
        check(source['body'] == body, 'source roundtrip')
        media = post['attachments'][0]['preview_url']
        check(bob.request('GET', media).startswith(b'\x89PNG'), 'member preview')
        other.request('GET', media, expected=404)
        check(not other.request('GET', '/api/v1/search?kind=posts&q=' + urllib.parse.quote('中文验收'))['items'], 'cross-site search leaked')
        check(other.request('GET', '/api/v1/notifications/unread-count')['count'] == 0, 'cross-site notification leaked')
        found = bob.request('GET', '/api/v1/search?kind=posts&q=' + urllib.parse.quote('中文验收'))
        check(any(item['id'] == pid for item in found['items']), 'Chinese search missing post')
        eventually(lambda: bob.request('GET', '/api/v1/notifications/unread-count')['count'] > 0, 'mention notification')
        bob.request('POST', f'/api/v1/posts/{pid}/likes', expected=204)
        bob.request('POST', f'/api/v1/posts/{pid}/replies', {'body': 'reply **rich** @alice', 'content_format': 'markdown'}, 201)
        eventually(lambda: alice.request('GET', '/api/v1/notifications/unread-count')['count'] > 0, 'like notification')
        self.note('9.3 content/search/notifications: sanitized Markdown, source, preview, Chinese search, mention and like')
        notifications = alice.request('GET', '/api/v1/notifications')
        alice.request('POST', '/api/v1/notifications/read-all', {'through_cursor': notifications['through_cursor']}, 204)
        check(alice.request('GET', '/api/v1/notifications/unread-count')['count'] == 0, 'snapshot mark-all did not clear current notifications')
        admin_read = a.request('GET', f'/api/v1/posts/{pid}')
        check(admin_read['id'] == pid, 'admin read')
        check(int(self.sql('a', 'SELECT count(*) FROM audit_events')) > 0, 'missing audit')
        alice.request('DELETE', f'/api/v1/communities/{gid}/members', {'actor': self.bob}, 204)
        bob.request('GET', media, expected=404)
        bob.request('GET', f'/api/v1/posts/{pid}', expected=(403, 404))
        check(not bob.request('GET', '/api/v1/search?kind=posts&q=' + urllib.parse.quote('中文验收'))['items'], 'search leaked after revoke')
        check(bob.request('GET', '/api/v1/notifications/unread-count')['count'] == 0, 'notification leaked after revoke')
        alice.request('PATCH', f'/api/v1/posts/{pid}', {'title': '已编辑', 'body': 'edited 中文', 'content_format': 'markdown', 'attachment_ids': []})
        alice.request('DELETE', f'/api/v1/posts/{pid}', expected=204)
        self.note('9.3 revocation/audit/mutations: current ACL, no stale search/count, audited admin read, edit/delete')

    def close(self):
        for process in self.processes:
            process.terminate()
        for process in self.processes:
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        for server in self.servers:
            server.shutdown()
            server.server_close()
        for log in self.logs:
            log.close()
        subprocess.run(['pg_ctl', '-D', str(self.root / 'pg'), '-m', 'fast', '-w', 'stop'], capture_output=True)

    def actor(self, target_db, origin, path, signer=None):
        # Bootstrap peer knowledge from its live representation. No post, event,
        # inbox receipt, delivery job or cached byte is seeded by the harness.
        obj = self.signed('b', signer, origin, path, expected=200) if signer else Client(origin, self.context).request('GET', path, headers={'Accept': 'application/activity+json'})
        fields = [obj['id'], obj['type'], obj['inbox'], obj['publicKey']['publicKeyPem']]
        self.sql(target_db, 'INSERT INTO actors(uri,kind,inbox_uri,public_key_pem) VALUES (' + ','.join(map(self.q, fields)) + ') ON CONFLICT(uri) DO UPDATE SET inbox_uri=EXCLUDED.inbox_uri,public_key_pem=EXCLUDED.public_key_pem')
        return obj

    def signed(self, db, actor, target_origin, path, payload=None, expected=202):
        key = self.sql(db, 'SELECT private_key_pem FROM actors WHERE uri=' + self.q(actor))
        check(bool(key), 'missing local signing key')
        key_path = self.root / 'request.key'
        key_path.write_text(key)
        os.chmod(key_path, 0o600)
        method = 'POST' if payload is not None else 'GET'
        data = json.dumps(payload, separators=(',', ':')).encode() if payload is not None else b''
        if payload is not None and payload['type'] == 'Follow':
            # Act as an outbound protocol client where a browser follow API is
            # absent: persist the original so canonical verification can GET it.
            self.sql(db, 'INSERT INTO activities(uri,actor_uri,kind) VALUES (' + ','.join(map(self.q, [payload['id'], actor, 'Follow'])) + ')')
            self.sql(db, 'INSERT INTO activity_payloads(activity_uri,original_payload,checksum) VALUES (' + self.q(payload['id']) + ",decode('" + data.hex() + "','hex'),decode('" + hashlib.sha256(data).hexdigest() + "','hex'))")
        date = email.utils.formatdate(usegmt=True)
        host = urllib.parse.urlsplit(target_origin).netloc
        canonical = f'(request-target): {method.lower()} {path}\nhost: {host}\ndate: {date}'
        hdr = {'Date': date, 'Content-Type': 'application/activity+json'}
        names = '(request-target) host date'
        if payload is not None:
            hdr['Digest'] = 'sha-256=' + base64.b64encode(hashlib.sha256(data).digest()).decode()
            canonical += '\ndigest: ' + hdr['Digest']
            names += ' digest'
        result = subprocess.run(['openssl', 'dgst', '-sha256', '-sign', str(key_path)], input=canonical.encode(), capture_output=True, check=True)
        hdr['Signature'] = f'keyId="{actor}#main-key",algorithm="rsa-sha256",headers="{names}",signature="{base64.b64encode(result.stdout).decode()}"'
        key_path.unlink()
        return Client(target_origin, self.context).request(method, path, data, expected, hdr)

    def replica(self, group, creator, target_db='b'):
        fields = [group['id'], group['actor_uri'], creator, 'federated', group['read_policy'], group['post_policy'], group['name'], group['title']]
        self.sql(target_db, 'INSERT INTO communities(id,actor_uri,creator_actor_uri,federation_mode,read_policy,post_policy,name,title) VALUES (' + ','.join(map(self.q, fields)) + ')')

    def exchange(self):
        a, b = self.instances['a']['client'], self.instances['b']['client']
        alice, alice_uri = self.alice_client, self.alice
        bob_uri = b.origin + '/users/admin'
        self.actor('b', a.origin, '/users/alice')
        self.actor('a', b.origin, '/users/admin')
        for db in ('a', 'b'):
            self.sql(db, "INSERT INTO peer_capabilities(domain,protected_reads) VALUES ('127.0.0.1',true)")
        follow = {'id': b.origin + '/activities/acceptance-person-follow', 'type': 'Follow', 'actor': bob_uri, 'object': alice_uri}
        self.signed('b', bob_uri, a.origin, '/users/alice/inbox', follow)
        avatar = alice.upload('avatar')
        alice.request('PATCH', '/api/v1/profile', {'display_name': 'Federated Alice', 'avatar_upload_id': avatar['id']})
        eventually(lambda: self.sql('b', 'SELECT display_name FROM profiles WHERE actor_uri=' + self.q(alice_uri)) == 'Federated Alice', 'live Person Update')
        self.note('9.4 Person Follow/Update delivered and avatar replaced across independent processes')
        for private in (False, True):
            name = 'private-exchange' if private else 'public-exchange'
            group = self.community(alice, name, private=private)
            gid, group_uri = group['id'], group['actor_uri']
            if private:
                alice.request('POST', f'/api/v1/communities/{gid}/members', {'actor': bob_uri}, 204)
            self.actor('b', a.origin, '/communities/' + name, bob_uri if private else None)
            self.replica(group, alice_uri)
            if private:
                # Initial known replica membership, before authoritative updates.
                self.sql('b', 'INSERT INTO community_members(community_id,actor_uri,approved_by) VALUES (' + ','.join(map(self.q, [gid, bob_uri, alice_uri])) + ') ON CONFLICT(community_id,actor_uri) DO UPDATE SET revoked_at=NULL')
            else:
                follow = {**follow, 'id': b.origin + '/activities/acceptance-group-follow', 'object': group_uri}
                self.signed('b', bob_uri, a.origin, '/communities/' + name + '/inbox', follow)
            upload = alice.upload()
            # Remote @mention resolution uses the actual peer WebFinger endpoint.
            body = 'live **Markdown** @admin@' + urllib.parse.urlsplit(b.origin).netloc + '\n\n![pixel](' + upload['reference'] + ')'
            post = alice.request('POST', f'/api/v1/communities/{gid}/topics', {'title': name, 'body': body, 'content_format': 'markdown', 'attachment_ids': [upload['id']]}, 201)
            object_uri = self.sql('a', 'SELECT object_uri FROM posts WHERE id=' + self.q(post['id']))
            remote_id = eventually(lambda: self.sql('b', 'SELECT id FROM posts WHERE object_uri=' + self.q(object_uri)), 'live Group Announce ' + name)
            viewed = b.request('GET', '/api/v1/posts/' + remote_id)
            check('<strong>Markdown</strong>' in viewed['body_html'], 'federated Markdown display')
            check(bool(viewed['attachments']), 'federated attachment missing')
            check(self.sql('a', 'SELECT count(*) FROM post_mentions WHERE post_id=' + self.q(post['id']) + ' AND active AND actor_uri=' + self.q(bob_uri)) == '1', 'remote mention resolution failed')
            eventually(lambda: b.request('GET', '/api/v1/notifications/unread-count')['count'] > 0, 'remote mention notification')
            if not private:
                remote_url = viewed['attachments'][0]['url']
                check(remote_url.startswith(a.origin + '/federation-media/'), 'public attachment not direct origin')
                check(self.sql('b', 'SELECT count(*) FROM media_private_cache') == '0', 'public cache metadata created')
                check(not any(path.startswith('/federation-media/') for method, path, status in self.instances['a']['proxy'].requests), 'backend prefetched public bytes')
                self.note('9.4 public Markdown/attachment: live Announce, direct origin, zero backend media fetch/cache')
            else:
                url = viewed['attachments'][0]['url']
                check(url.startswith('/api/v1/media/private/'), 'private attachment exposed origin URL')
                check(b.request('GET', url).startswith(b'\x89PNG'), 'private original fetch')
                check(b.request('GET', url + '/preview').startswith(b'\x89PNG'), 'private preview')
                cache_id = url.rsplit('/', 1)[1]
                generation = self.sql('b', 'SELECT generation FROM media_private_cache WHERE id=' + self.q(cache_id))
                expiry = self.sql('b', 'SELECT expires_at FROM media_private_cache WHERE id=' + self.q(cache_id))
                b.request('GET', url)
                check(expiry == self.sql('b', 'SELECT expires_at FROM media_private_cache WHERE id=' + self.q(cache_id)), 'cache hit renewed expiry')
                self.note('9.4 private media: Actor-signed origin fetch, original/preview, hits do not renew expiry')
                # Real configured minimum retention is 60s; wait for periodic cleanup.
                eventually(lambda: self.sql('b', 'SELECT state FROM media_private_cache WHERE id=' + self.q(cache_id)) == 'missing', 'periodic private expiry cleanup', timeout=75)
                check(not (self.root / 'media-b' / 'private-cache' / generation).exists() and not (self.root / 'media-b' / 'previews' / generation).exists(), 'expired cache bytes remained on disk')
                check(b.request('GET', url).startswith(b'\x89PNG'), 'private refetch after expiry')
                alice.request('DELETE', f'/api/v1/communities/{gid}/members', {'actor': bob_uri}, 204)
                eventually(lambda: self.sql('b', 'SELECT count(*) FROM community_members WHERE community_id=' + self.q(gid) + ' AND actor_uri=' + self.q(bob_uri) + ' AND revoked_at IS NULL') == '0', 'live membership revocation')
                b.request('GET', url, expected=404)
                self.note('9.4 private media: real expiry, periodic byte deletion, authorized refetch and propagated revocation')
                # After revocation this recipient must not receive later edits.
                continue
            alice.request('PATCH', '/api/v1/posts/' + post['id'], {'title': name, 'body': 'updated **exchange**', 'content_format': 'markdown', 'attachment_ids': []})
            eventually(lambda: 'updated <strong>exchange</strong>' in self.sql('b', 'SELECT body FROM posts WHERE id=' + self.q(remote_id)), 'live rich Update')
        reverse_follow = {'id': a.origin + '/activities/acceptance-reverse-person', 'type': 'Follow', 'actor': alice_uri, 'object': bob_uri}
        self.signed('a', alice_uri, b.origin, '/users/admin/inbox', reverse_follow)
        b.request('PATCH', '/api/v1/profile', {'display_name': 'Reverse Admin'})
        eventually(lambda: self.sql('a', 'SELECT display_name FROM profiles WHERE actor_uri=' + self.q(bob_uri)) == 'Reverse Admin', 'reverse Person Update')
        reverse = self.community(b, 'reverse-exchange')
        self.actor('a', b.origin, '/communities/reverse-exchange')
        self.replica(reverse, bob_uri, 'a')
        reverse_follow = {**reverse_follow, 'id': a.origin + '/activities/acceptance-reverse-group', 'object': reverse['actor_uri']}
        self.signed('a', alice_uri, b.origin, '/communities/reverse-exchange/inbox', reverse_follow)
        upload = b.upload()
        body = 'reverse **rich** @alice@' + urllib.parse.urlsplit(a.origin).netloc + '\n\n![pixel](' + upload['reference'] + ')'
        post = b.request('POST', '/api/v1/communities/' + reverse['id'] + '/topics', {'title': 'reverse post', 'body': body, 'content_format': 'markdown', 'attachment_ids': [upload['id']]}, 201)
        object_uri = self.sql('b', 'SELECT object_uri FROM posts WHERE id=' + self.q(post['id']))
        received = eventually(lambda: self.sql('a', 'SELECT id FROM posts WHERE object_uri=' + self.q(object_uri)), 'reverse rich Announce')
        check('<strong>rich</strong>' in alice.request('GET', '/api/v1/posts/' + received)['body_html'], 'reverse rich display')
        eventually(lambda: self.sql('a', 'SELECT count(*) FROM post_mentions WHERE post_id=' + self.q(received) + ' AND active AND actor_uri=' + self.q(alice_uri)) == '1', 'reverse mention metadata')
        b.request('PATCH', '/api/v1/posts/' + post['id'], {'title': 'reverse post', 'body': 'reverse updated', 'content_format': 'markdown', 'attachment_ids': []})
        eventually(lambda: 'reverse updated' in self.sql('a', 'SELECT body FROM posts WHERE id=' + self.q(received)), 'reverse rich Update')
        self.note('9.4 reverse direction: Person Update, rich Create/Update, attachment and canonical mention')
        local = self.community(alice, 'local-exchange', local=True)
        post = alice.request('POST', '/api/v1/communities/' + local['id'] + '/topics', {'title': 'local only', 'body': 'never export @admin@' + urllib.parse.urlsplit(b.origin).netloc, 'content_format': 'markdown'}, 201)
        check(self.sql('b', "SELECT count(*) FROM posts WHERE title='local only'") == '0', 'local-only post exported')
        check(self.sql('a', 'SELECT count(*) FROM activities WHERE community_id=' + self.q(local['id'])) == '0', 'local-only activity generated')
        self.note('9.4 local-only content creates no federated activity or remote post')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--local-only', action='store_true', help='run the 9.3 matrix without peer exchange')
    parser.add_argument('--report', type=Path, help='write a sanitized successful-run JSON evidence report')
    args = parser.parse_args()
    root = tempfile.mkdtemp(prefix='commune-participation-acceptance.')
    print('artifacts: ' + root, flush=True)
    test = Acceptance(root)
    try:
        test.start()
        test.local()
        if not args.local_only:
            test.exchange()
        if args.report:
            report = {'date': time.strftime('%Y-%m-%d'), 'source_base': run(['git', 'rev-parse', 'HEAD']), 'source_has_uncommitted_changes': bool(run(['git', 'status', '--porcelain'])),
                      'binary_sha256': hashlib.sha256(Path(test.binary).read_bytes()).hexdigest(), 'postgres': run(['postgres', '--version']),
                      'go': run(['go', 'version']), 'python': run(['python3', '--version']), 'processes': [p.pid for p in test.processes],
                      'passed': test.events, 'peer_acceptance_9_5': 'not run',
                      'transport': 'loopback HTTPS with temporary trusted certificate; TLS verification enabled',
                      'bootstrap': 'peer Actors/replica metadata from live GET; initial private membership; outbound Follow canonical payloads only',
                      'requests': {name: instance['proxy'].requests for name, instance in test.instances.items()}}
            args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    finally:
        test.close()
        # Retain logs/configs only on explicit request; configs contain test secrets.
        if not os.environ.get('COMMUNE_ACCEPTANCE_KEEP'):
            shutil.rmtree(root)


if __name__ == '__main__':
    main()
