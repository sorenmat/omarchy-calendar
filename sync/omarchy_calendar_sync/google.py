"""Local Google desktop OAuth and multi-account sync. No hosted service."""
import argparse
import base64
from contextlib import contextmanager
from datetime import datetime, timedelta, timezone
import fcntl
import hashlib
import html
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import re
import secrets
import subprocess
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qs, quote, urlencode, urlsplit
from urllib.request import Request, urlopen

from .cli import resolve_local_timezone, write_atomic
from .normalize import normalize_all, _https_only

SCOPES = ['openid', 'email', 'https://www.googleapis.com/auth/calendar.calendarlist.readonly',
          'https://www.googleapis.com/auth/calendar.events']
TOKEN_URL = 'https://oauth2.googleapis.com/token'
API = 'https://www.googleapis.com/calendar/v3'
APP = 'smo.calendar'
DEFAULT_CLIENT_PATH = Path(__file__).resolve().parents[2] / 'oauth-client.json'


class CalendarError(Exception):
    pass


def request_json(url, data=None, token=None, method=None):
    headers = {'Accept': 'application/json'}
    if token:
        headers['Authorization'] = 'Bearer ' + token
    body = (json.dumps(data).encode() if method == 'PATCH' else urlencode(data).encode()) if data is not None else None
    if body is not None:
        headers['Content-Type'] = 'application/json' if method == 'PATCH' else 'application/x-www-form-urlencoded'
    try:
        with urlopen(Request(url, data=body, headers=headers, method=method), timeout=25) as response:
            return json.load(response)
    except HTTPError as error:
        # Never echo provider bodies: they can contain account data or tokens.
        if error.code == 401:
            raise CalendarError('Google authorization expired. Reconnect this account.') from None
        if error.code == 403:
            raise CalendarError('Access denied. Reconnect this account to grant Calendar permissions, or check calendar access.') from None
        raise CalendarError(f'Google request failed (HTTP {error.code}). Try reconnecting if it persists.') from None
    except (URLError, TimeoutError, ValueError):
        raise CalendarError('Could not reach Google. Cached events are still available.') from None


def keyring(action, key, value=None, missing_ok=False):
    command = ['secret-tool', action]
    if action == 'store':
        command += ['--label=Omarchy Calendar']
    command += ['application', APP, 'account', key]
    try:
        result = subprocess.run(command, input=json.dumps(value) if value is not None else None,
                                text=True, capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        raise CalendarError('Desktop keyring unavailable. Install secret-tool and unlock your keyring.') from None
    if result.returncode:
        if action == 'lookup' and missing_ok and result.returncode == 1 and not result.stderr.strip():
            return None
        if action == 'lookup':
            raise CalendarError('Credentials unavailable. Unlock your keyring or reconnect the account.')
        raise CalendarError('Could not update the desktop keyring. Unlock it and try again.')
    return json.loads(result.stdout) if action == 'lookup' else None


def read_document(folder):
    path = folder / 'events.json'
    if not path.exists():
        return {'version': 1, 'source': 'Google Calendar', 'syncedAt': '', 'accounts': [], 'calendars': [], 'events': []}
    try:
        doc = json.loads(path.read_text())
        if doc.get('version') != 1 or not all(isinstance(doc.get(k), list) for k in ('accounts', 'calendars', 'events')):
            raise ValueError()
        return doc
    except (ValueError, AttributeError):
        raise CalendarError('Calendar cache is unreadable; restore or move events.json before continuing.') from None


@contextmanager
def locked(folder):
    folder.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (folder / 'sync.lock').open('w') as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise CalendarError('Another calendar operation is running. Try again shortly.') from None
        yield


def oauth_callback(target, expected_state):
    """Return a code only for the callback path and the original random state."""
    parsed = urlsplit(target)
    query = parse_qs(parsed.query)
    if parsed.path != '/callback' or query.get('state') != [expected_state]:
        return None
    if query.get('error'):
        raise CalendarError('Google sign-in was cancelled or denied.')
    codes = query.get('code', [])
    return codes[0] if len(codes) == 1 and codes[0] else None


def authorize(client, expected_account=None):
    verifier = secrets.token_urlsafe(64)
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip('=')
    state = secrets.token_urlsafe(32)
    outcome = {}

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_GET(self):
            try:
                code = oauth_callback(self.path, state)
                if code:
                    outcome['code'] = code
            except CalendarError as error:
                outcome['error'] = str(error)
            valid = bool(outcome)
            self.send_response(200 if valid else 400)
            self.send_header('Content-Type', 'text/plain; charset=utf-8')
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(b'Return to Omarchy Calendar to finish connecting.' if valid else b'Invalid callback.')

    class CallbackServer(HTTPServer):
        def get_request(self):
            connection, address = super().get_request()
            connection.settimeout(3)
            return connection, address

    with CallbackServer(('127.0.0.1', 0), Handler) as server:
        server.timeout = 1
        redirect = f'http://127.0.0.1:{server.server_port}/callback'
        params = dict(client_id=client['client_id'], redirect_uri=redirect, response_type='code',
                      scope=' '.join(SCOPES), access_type='offline', prompt='consent select_account',
                      state=state, code_challenge=challenge, code_challenge_method='S256')
        url = 'https://accounts.google.com/o/oauth2/v2/auth?' + urlencode(params)
        subprocess.Popen(['xdg-open', url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 180
        while not outcome and time.monotonic() < deadline:
            server.handle_request()
    if 'error' in outcome:
        raise CalendarError(outcome['error'])
    if not outcome:
        raise CalendarError('Sign-in timed out. Click Connect to try again.')
    tokens = request_json(TOKEN_URL, dict(client, code=outcome['code'], code_verifier=verifier,
                                         redirect_uri=redirect, grant_type='authorization_code'))
    required = set(SCOPES[2:])
    if not required.issubset(set(tokens.get('scope', '').split())):
        raise CalendarError('Calendar permissions were not granted. Reconnect and enable both calendar permissions.')
    if not tokens.get('refresh_token'):
        raise CalendarError('Google did not return offline access. Reconnect and grant consent.')
    user = request_json('https://openidconnect.googleapis.com/v1/userinfo', token=tokens['access_token'])
    if not user.get('sub') or not user.get('email') or not user.get('email_verified'):
        raise CalendarError('Google did not return a verified account identity.')
    if expected_account and user['sub'] != expected_account:
        raise CalendarError('You selected a different account. Reconnect the original account or use Add account.')
    return user, dict(client, refresh_token=tokens['refresh_token'])


def load_client(path):
    """Read only the desktop registration; never accept web clients or endpoint overrides."""
    try:
        installed = json.loads(Path(path).expanduser().read_text())['installed']
        client = {key: installed[key] for key in ('client_id', 'client_secret')}
        if not all(isinstance(v, str) and v for v in client.values()):
            raise ValueError()
        return client
    except (OSError, ValueError, KeyError, TypeError):
        raise CalendarError('Choose a Google Desktop app credentials JSON file.') from None


def connect(folder, client_path=None, account_id=None):
    if client_path:
        client = load_client(client_path)
        keyring('store', 'desktop-client', client)
    elif account_id:
        stored = keyring('lookup', account_id)
        client = {key: stored[key] for key in ('client_id', 'client_secret')}
    else:
        client = keyring('lookup', 'desktop-client', missing_ok=True)
        if client is None:
            if not DEFAULT_CLIENT_PATH.exists():
                raise CalendarError('The shared Google app is not configured yet. You can import a Desktop credentials JSON under Advanced setup.')
            client = load_client(DEFAULT_CLIENT_PATH)
    user, credentials = authorize(client, account_id)
    with locked(folder):
        doc = read_document(folder)
        keyring('store', user['sub'], credentials)
        previous = next((a for a in doc['accounts'] if a['id'] == user['sub']), {})
        doc['accounts'] = [a for a in doc['accounts'] if a['id'] != user['sub']]
        doc['accounts'].append(dict(previous, id=user['sub'], email=user['email'], error=''))
        write_atomic(folder / 'events.json', doc)
    sync(folder)


def list_all(path, token, params=None):
    params = dict(params or {})
    rows = []
    while True:
        response = request_json(API + path + '?' + urlencode(params), token=token)
        rows.extend(response.get('items', []))
        page = response.get('nextPageToken')
        if not page:
            return rows
        params['pageToken'] = page


def fetch_account(account, now, tz):
    credentials = keyring('lookup', account['id'])
    tokens = request_json(TOKEN_URL, dict(credentials, grant_type='refresh_token'))
    token = tokens['access_token']
    calendars, events = [], []
    # Fetch each account transactionally. A failed calendar retains that account's last good cache.
    for raw in list_all('/users/me/calendarList', token):
        if raw.get('deleted') or raw.get('accessRole') in ('none', 'freeBusyReader'):
            continue
        color = raw.get('backgroundColor', '')
        calendar = dict(id=account['id'] + ':' + raw['id'], googleId=raw['id'], accountId=account['id'],
                        accountEmail=account['email'], primary=raw.get('primary', False), name=raw.get('summaryOverride') or raw.get('summary') or raw['id'],
                        color=color if re.fullmatch(r'#[0-9a-fA-F]{6}', color) else '#89b4fa')
        calendars.append(calendar)
        params = dict(timeMin=(now - timedelta(days=31)).isoformat(),
                      timeMax=(now + timedelta(days=93)).isoformat(),
                      singleEvents='true', orderBy='startTime', maxResults=2500)
        for event in list_all('/calendars/' + quote(raw['id'], safe='') + '/events', token, params):
            for row in normalize_all([event], calendar, tz):
                row.update(accountId=account['id'], accountEmail=account['email'], iCalUID=event.get('iCalUID', ''))
                attendee = own_attendee(event, account, calendar)
                row['canRespond'] = bool(attendee and not attendee.get('organizer') and raw.get('accessRole') in ('owner', 'writer'))
                events.append(row)
    return calendars, events


def own_attendee(event, account, calendar):
    return next((a for a in (event.get('attendees') or []) if a.get('self') and
                 (calendar.get('primary') or a.get('email', '').lower() == account['email'].lower())), None)


def respond(folder, account_id, calendar_id, event_id, response):
    if response not in ('accepted', 'declined'):
        raise CalendarError('Choose Accept or Reject.')
    with locked(folder):
        doc = read_document(folder)
        account = next((a for a in doc['accounts'] if a['id'] == account_id), None)
        calendar = next((c for c in doc['calendars'] if c['id'] == calendar_id and c['accountId'] == account_id), None)
        rows = [e for e in doc['events'] if e.get('accountId') == account_id and e['calendarId'] == calendar_id and e['id'] == event_id]
        if not account or not calendar or not rows or not rows[0].get('canRespond'):
            raise CalendarError('This invitation cannot be answered here. Refresh your calendar or open the event.')
        credentials = keyring('lookup', account_id)
        tokens = request_json(TOKEN_URL, dict(credentials, grant_type='refresh_token'))
        if 'scope' in tokens and SCOPES[-1] not in tokens['scope'].split():
            raise CalendarError('Reconnect this account in settings to enable Accept and Reject.')
        url = API + '/calendars/' + quote(calendar['googleId'], safe='') + '/events/' + quote(event_id, safe='')
        event = request_json(url, token=tokens['access_token'])
        attendee = own_attendee(event, account, calendar)
        if event.get('status') == 'cancelled' or not attendee or attendee.get('organizer') or attendee.get('responseStatus') not in ('needsAction', 'tentative'):
            raise CalendarError('This invitation is no longer pending. Refresh your calendar.')
        # attendeesOmitted updates only this response, preserving all other guests.
        request_json(url + '?sendUpdates=all', {'attendeesOmitted': True, 'attendees': [
            {'email': attendee['email'], 'responseStatus': response}]}, token=tokens['access_token'], method='PATCH')
        for row in rows:
            row['responseStatus'] = response
        write_atomic(folder / 'events.json', doc)


def sync(folder):
    with locked(folder):
        doc = read_document(folder)
        now = datetime.now(timezone.utc)
        for account in doc['accounts']:
            try:
                calendars, events = fetch_account(account, now, resolve_local_timezone())
                doc['calendars'] = [c for c in doc['calendars'] if c['accountId'] != account['id']] + calendars
                doc['events'] = [e for e in doc['events'] if e['accountId'] != account['id']] + events
                account.update(error='', syncedAt=now.isoformat())
            except CalendarError as error:
                account['error'] = str(error)
            except (KeyError, TypeError, ValueError):
                account['error'] = 'Sync failed. Check your connection and keyring, or reconnect this account.'
        doc.update(syncedAt=now.isoformat(), windowStart=(now - timedelta(days=31)).date().isoformat(),
                   windowEnd=(now + timedelta(days=93)).date().isoformat())
        doc['events'].sort(key=lambda e: (e['dateKey'], not e['allDay'], e['start'], e['title']))
        write_atomic(folder / 'events.json', doc)
        return doc


def remove(folder, account_id):
    with locked(folder):
        doc = read_document(folder)
        if not any(a['id'] == account_id for a in doc['accounts']):
            raise CalendarError('Account not found.')
        keyring('clear', account_id)
        doc['accounts'] = [a for a in doc['accounts'] if a['id'] != account_id]
        doc['calendars'] = [c for c in doc['calendars'] if c['accountId'] != account_id]
        doc['events'] = [e for e in doc['events'] if e['accountId'] != account_id]
        write_atomic(folder / 'events.json', doc)


def notify_start(folder, alerts):
    """One notification per occurrence, shared by all monitors and shell restarts."""
    folder = folder / 'alerts'
    with locked(folder):
        path = folder / 'notified.json'
        sent = json.loads(path.read_text()) if path.exists() else {}
        now = time.time() * 1000
        sent = {key: start for key, start in sent.items() if now - start < 86400000}
        for alert in alerts:
            key = hashlib.sha256(alert['key'].encode()).hexdigest()
            if key in sent or not 0 <= now - alert['start'] < 60000:
                continue
            url = _https_only(alert['url'])
            action = ['xdg-open', url] if url else ['omarchy-shell', APP, 'open']
            command = ['omarchy', 'notification', 'send', '--app-name', APP,
                       '-u', 'normal', '-g', '󰃭', '-t', '60000',
                       html.escape(alert['title']), html.escape(alert['body']), '--exec', *action]
            try:
                subprocess.run(command, check=True, capture_output=True, timeout=10)
            except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
                raise CalendarError('Could not show the event notification.') from None
            sent[key] = alert['start']
            write_atomic(path, sent)


def main(argv=None):
    os.umask(0o077)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--state-dir', type=Path, default=Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / APP)
    commands = parser.add_subparsers(dest='command', required=True)
    commands.add_parser('sync')
    commands.add_parser('status')
    commands.add_parser('notify').add_argument('alerts', help='JSON start alerts from the widget')
    add = commands.add_parser('connect')
    add.add_argument('--client', help='Google Desktop app credentials JSON')
    add.add_argument('--account', help='Reconnect an existing account')
    commands.add_parser('remove').add_argument('account')
    reply = commands.add_parser('respond')
    reply.add_argument('account')
    reply.add_argument('calendar')
    reply.add_argument('event')
    reply.add_argument('response', choices=('accepted', 'declined'))
    args = parser.parse_args(argv)
    try:
        if args.command == 'notify':
            notify_start(args.state_dir, json.loads(args.alerts))
            return 0
        if args.command == 'connect':
            connect(args.state_dir, args.client, args.account)
        elif args.command == 'sync':
            sync(args.state_dir)
        elif args.command == 'remove':
            remove(args.state_dir, args.account)
        elif args.command == 'respond':
            respond(args.state_dir, args.account, args.calendar, args.event, args.response)
        doc = read_document(args.state_dir)
        print(json.dumps({'accounts': doc['accounts'], 'eventCount': len(doc['events'])}))
    except (CalendarError, OSError) as error:
        print(json.dumps({'error': str(error)}))
        return 1
    except (KeyError, TypeError, ValueError):
        print(json.dumps({'error': 'Could not read Google credentials or response. Try reconnecting the account.'}))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
