"""Checks for the OAuth boundary and independent account caches (no live Google calls)."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from omarchy_calendar_sync import google


class GoogleTests(unittest.TestCase):
    def test_rsvp_targets_own_occurrence_and_only_updates_cache_after_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            doc = google.read_document(folder)
            account = dict(id='work', email='me@example.com')
            calendar = dict(id='work:c', accountId='work', googleId='me@example.com', primary=True)
            row = dict(id='instance/one', accountId='work', calendarId='work:c', canRespond=True,
                       responseStatus='needsAction', dateKey='2026-09-08')
            doc.update(accounts=[account], calendars=[calendar], events=[row, dict(row, dateKey='2026-09-09'),
                dict(row, accountId='personal'), dict(row, id='instance/two')])
            google.write_atomic(folder / 'events.json', doc)
            own = dict(email='me@example.com', self=True, responseStatus='needsAction')
            raw = dict(attendees=[dict(email='other@example.com', responseStatus='accepted'), own])
            token = dict(access_token='access', scope=' '.join(google.SCOPES))
            with patch.object(google, 'keyring', return_value={}) as keyring, patch.object(google, 'request_json') as request:
                request.side_effect = [token, raw, google.CalendarError('offline')]
                with self.assertRaisesRegex(google.CalendarError, 'offline'):
                    google.respond(folder, 'work', 'work:c', 'instance/one', 'accepted')
                self.assertEqual(google.read_document(folder), doc)
                for response in ('accepted', 'declined'):
                    request.side_effect = [token, raw, {}]
                    google.respond(folder, 'work', 'work:c', 'instance/one', response)
                    args, kwargs = request.call_args
                    self.assertEqual(args[0], google.API + '/calendars/me%40example.com/events/instance%2Fone?sendUpdates=all')
                    self.assertEqual(args[1], {'attendeesOmitted': True, 'attendees': [{'email': own['email'], 'responseStatus': response}]})
                    self.assertEqual(kwargs, dict(token='access', method='PATCH'))
                    statuses = [e['responseStatus'] for e in google.read_document(folder)['events']]
                    self.assertEqual(statuses, [response, response, 'needsAction', 'needsAction'])
                    keyring.assert_called_with('lookup', 'work')
                for attendee in (dict(own, responseStatus='accepted'), dict(own, organizer=True), dict(own, self=False)):
                    request.side_effect = [token, dict(attendees=[attendee])]
                    with self.assertRaisesRegex(google.CalendarError, 'no longer pending'):
                        google.respond(folder, 'work', 'work:c', 'instance/one', 'accepted')
                request.side_effect = [dict(token, scope='https://www.googleapis.com/auth/calendar.events.readonly')]
                with self.assertRaisesRegex(google.CalendarError, 'Reconnect'):
                    google.respond(folder, 'work', 'work:c', 'instance/one', 'accepted')
                request.reset_mock()
                with self.assertRaises(google.CalendarError):
                    google.respond(folder, 'personal', 'work:c', 'instance/one', 'accepted')
                request.assert_not_called()
            self.assertIsNone(google.own_attendee(raw, dict(account, email='someone@example.com'), dict(calendar, primary=False)))

    def test_sync_exposes_rsvp_only_for_own_writable_invitation(self):
        from datetime import datetime, timezone
        account = dict(id='work', email='me@example.com')
        calendar = dict(id='me@example.com', primary=True, accessRole='owner')
        attendee = dict(email='me@example.com', self=True, responseStatus='needsAction')
        event = dict(id='event', attendees=[attendee], start={'dateTime': '2026-09-08T10:00:00Z'},
                     end={'dateTime': '2026-09-08T11:00:00Z'})
        cases = [(calendar, event, True), (dict(calendar, accessRole='reader'), event, False),
                 (calendar, dict(event, attendees=[dict(attendee, organizer=True)]), False),
                 (dict(calendar, primary=False), dict(event, attendees=[dict(attendee, email='other@example.com')]), False),
                 (calendar, dict(event, attendees=None), False)]
        with patch.object(google, 'keyring', return_value={}), patch.object(google, 'request_json', return_value={'access_token': 'access'}), patch.object(google, 'list_all') as listing:
            for raw_calendar, raw_event, expected in cases:
                listing.side_effect = [[raw_calendar], [raw_event]]
                _, rows = google.fetch_account(account, datetime.now(timezone.utc), timezone.utc)
                self.assertEqual(rows[0]['canRespond'], expected)

    def test_patch_uses_json_and_oauth_keeps_form_encoding(self):
        with patch.object(google, 'urlopen') as open_url:
            open_url.return_value.__enter__.return_value.read.return_value = '{}'
            body = {'attendeesOmitted': True, 'attendees': [{'email': 'me@example.com', 'responseStatus': 'accepted'}]}
            google.request_json(google.API + '/event', body, token='private', method='PATCH')
            request = open_url.call_args.args[0]
            self.assertEqual(request.method, 'PATCH')
            self.assertEqual(request.get_header('Content-type'), 'application/json')
            self.assertEqual(json.loads(request.data), body)
            google.request_json(google.TOKEN_URL, {'grant_type': 'refresh_token'})
            request = open_url.call_args.args[0]
            self.assertEqual(request.get_method(), 'POST')
            self.assertEqual(request.data, b'grant_type=refresh_token')

    def test_start_notifications_are_clickable_and_persist_deduplication(self):
        now = 1788861600000
        alert = dict(key='shared-occurrence', start=now, title='Starting now: <Review>',
                     body='Click to join meeting', url='https://meet.google.com/abc?authuser=work%40example.com')
        with tempfile.TemporaryDirectory() as tmp, patch.object(google.time, 'time', return_value=now / 1000), patch.object(google.subprocess, 'run') as run:
            folder = Path(tmp)
            google.notify_start(folder, [alert, alert])
            google.notify_start(folder, [alert])
            run.assert_called_once()
            command = run.call_args.args[0]
            self.assertEqual(command[-3:], ['--exec', 'xdg-open', alert['url']])
            self.assertIn('Starting now: &lt;Review&gt;', command)
            saved = folder / 'alerts/notified.json'
            self.assertNotIn('Review', saved.read_text())
            self.assertEqual(saved.stat().st_mode & 0o777, 0o600)
            google.notify_start(folder, [dict(alert, key='event', url='javascript:bad')])
            self.assertEqual(run.call_args.args[0][-4:], ['--exec', 'omarchy-shell', google.APP, 'open'])
            google.notify_start(folder, [dict(alert, key='old', start=now - 60000), dict(alert, key='future', start=now + 1)])
            self.assertEqual(run.call_count, 2)

    def test_failed_notification_can_retry_and_alert_lock_is_independent_of_sync(self):
        alert = dict(key='event', start=100000, title='Starting now: Review', body='Click to open event', url='https://calendar.google.com/calendar/event?eid=sample')
        with tempfile.TemporaryDirectory() as tmp, patch.object(google.time, 'time', return_value=100), patch.object(google.subprocess, 'run') as run:
            folder = Path(tmp)
            run.side_effect = google.subprocess.CalledProcessError(1, 'omarchy')
            with self.assertRaises(google.CalendarError):
                google.notify_start(folder, [alert])
            run.side_effect = None
            with google.locked(folder):
                google.notify_start(folder, [alert])
            self.assertEqual(run.call_count, 2)
            with google.locked(folder / 'alerts'), self.assertRaises(google.CalendarError):
                google.notify_start(folder, [alert])

    def test_shared_client_is_used_without_import_and_overrides_win(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            registration = folder / 'oauth-client.json'
            shared = {'client_id': 'shared-client', 'client_secret': 'desktop-value'}
            registration.write_text(json.dumps({'installed': dict(shared, token_uri='https://ignored.invalid')}))
            user = {'sub': '123', 'email': 'me@example.com'}
            with patch.object(google, 'DEFAULT_CLIENT_PATH', registration), patch.object(google, 'keyring', return_value=None), patch.object(google, 'authorize', return_value=(user, {'refresh_token': 'private'})) as auth, patch.object(google, 'sync'):
                google.connect(folder)
                auth.assert_called_once_with(shared, None)
            override = {'client_id': 'personal-client', 'client_secret': 'personal-value'}
            with patch.object(google, 'DEFAULT_CLIENT_PATH', registration), patch.object(google, 'keyring', return_value=override), patch.object(google, 'authorize', return_value=(user, {})) as auth, patch.object(google, 'sync'):
                google.connect(folder)
                auth.assert_called_once_with(override, None)
            self.assertNotIn('private', (folder / 'events.json').read_text())

    def test_web_client_is_not_accepted_as_desktop_registration(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'oauth.json'
            path.write_text(json.dumps({'web': {'client_id': 'web', 'client_secret': 'value'}}))
            with self.assertRaisesRegex(google.CalendarError, 'Desktop'):
                google.load_client(path)

    def test_missing_keyring_item_is_distinct_from_keyring_failure(self):
        with patch.object(google.subprocess, 'run') as run:
            run.return_value.returncode = 1
            run.return_value.stderr = ''
            self.assertIsNone(google.keyring('lookup', 'desktop-client', missing_ok=True))
            run.return_value.stderr = 'Keyring is locked'
            with self.assertRaises(google.CalendarError):
                google.keyring('lookup', 'desktop-client', missing_ok=True)

    def test_authorize_sends_pkce_and_rejects_wrong_account(self):
        from urllib.parse import parse_qs, urlsplit
        opened = {}

        class FakeServer:
            server_port = 12345
            def __init__(self, address, handler):
                self.handler = handler
                self.assert_address = address
            def __enter__(self):
                return self
            def __exit__(self, *_):
                pass
            def handle_request(self):
                # Feed the handler without opening a socket.
                from io import BytesIO
                handler = object.__new__(self.handler)
                handler.path = '/callback?code=one-use-code&state=' + opened['state'][0]
                handler.send_response = lambda *_: None
                handler.send_header = lambda *_: None
                handler.end_headers = lambda: None
                handler.wfile = BytesIO()
                handler.do_GET()

        def browser(argv, **_):
            opened.update(parse_qs(urlsplit(argv[1]).query))

        def request(url, data=None, token=None):
            if url == google.TOKEN_URL:
                challenge = google.base64.urlsafe_b64encode(google.hashlib.sha256(data['code_verifier'].encode()).digest()).decode().rstrip('=')
                self.assertEqual(opened['code_challenge'], [challenge])
                self.assertEqual(opened['code_challenge_method'], ['S256'])
                self.assertEqual(data['redirect_uri'], 'http://127.0.0.1:12345/callback')
                return {'access_token':'access','refresh_token':'refresh','scope':' '.join(google.SCOPES)}
            self.assertEqual(token, 'access')
            return {'sub':'123','email':'me@example.com','email_verified':True}

        with patch.object(google, 'HTTPServer', FakeServer), patch.object(google.subprocess, 'Popen', side_effect=browser), patch.object(google, 'request_json', side_effect=request):
            user, credentials = google.authorize({'client_id':'client','client_secret':'secret'})
            self.assertEqual(user['sub'], '123')
            self.assertEqual(credentials['refresh_token'], 'refresh')
            self.assertNotIn('access_token', credentials)
            with self.assertRaisesRegex(google.CalendarError, 'different account'):
                google.authorize({'client_id':'client','client_secret':'secret'}, 'wrong-account')

    def test_callback_requires_state_and_exact_path(self):
        self.assertEqual(google.oauth_callback('/callback?code=ok&state=random', 'random'), 'ok')
        for path in ['/callback?code=stolen&state=wrong', '/other?code=ok&state=random',
                     '/callback?code=a&code=b&state=random', '/callback?code=a&state=random&state=random']:
            self.assertIsNone(google.oauth_callback(path, 'random'))
        with self.assertRaises(google.CalendarError):
            google.oauth_callback('/callback?error=access_denied&state=random', 'random')

    def test_pagination_keeps_filters(self):
        with patch.object(google, 'request_json', side_effect=[{'items': [1], 'nextPageToken': 'next'}, {'items': [2]}]) as request:
            self.assertEqual(google.list_all('/users/me/calendarList', 'token', {'maxResults': 100}), [1, 2])
            self.assertIn('pageToken=next', request.call_args.args[0])
            self.assertIn('maxResults=100', request.call_args.args[0])

    def test_independent_accounts_keep_failed_cache_and_empty_calendars(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            doc = google.read_document(folder)
            doc['accounts'] = [{'id':'personal','email':'me@example.com'}, {'id':'work','email':'me@work.example'}]
            old = dict(accountId='work', calendarId='work:c', id='old', dateKey='2026-09-08',
                       start='2026-09-08T12:00:00Z', end='2026-09-08T13:00:00Z', title='Cached', allDay=False)
            doc['events'] = [old]
            doc['calendars'] = [{'accountId':'work','id':'work:c','name':'Work'}]
            google.write_atomic(folder/'events.json', doc)
            def fetch(account, *_):
                if account['id'] == 'work':
                    raise google.CalendarError('Offline')
                return [{'accountId':'personal','id':'personal:c','name':'Empty calendar'}], []
            with patch.object(google, 'fetch_account', side_effect=fetch):
                result = google.sync(folder)
            self.assertEqual(result['events'], [old])
            self.assertEqual(len(result['calendars']), 2)
            self.assertEqual(result['accounts'][0]['error'], '')
            self.assertTrue(result['accounts'][1]['error'])
            self.assertEqual((folder/'events.json').stat().st_mode & 0o777, 0o600)

    def test_remove_only_selected_account(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp); doc=google.read_document(folder)
            doc['accounts']=[{'id':'a'}, {'id':'b'}]
            doc['events']=[{'accountId':'a'}, {'accountId':'b'}]
            doc['calendars']=[{'accountId':'a'}, {'accountId':'b'}]
            google.write_atomic(folder/'events.json', doc)
            with patch.object(google,'keyring') as keyring:
                google.remove(folder,'a')
                keyring.assert_called_once_with('clear','a')
            result=google.read_document(folder)
            self.assertEqual(result['accounts'],[{'id':'b'}])
            self.assertEqual(result['events'],[{'accountId':'b'}])

    def test_corrupt_cache_is_not_silently_overwritten(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder=Path(tmp); path=folder/'events.json'; path.write_text('broken')
            with self.assertRaises(google.CalendarError):
                google.sync(folder)
            self.assertEqual(path.read_text(),'broken')

    def test_keyring_receives_secrets_on_stdin_only(self):
        with patch.object(google.subprocess,'run') as run:
            run.return_value.returncode=0
            google.keyring('store','123',{'refresh_token':'secret-token'})
            self.assertNotIn('secret-token', ' '.join(run.call_args.args[0]))
            self.assertIn('secret-token',run.call_args.kwargs['input'])

    def test_fetch_namespaces_same_calendar_across_accounts(self):
        from datetime import datetime, timezone
        event={'id':'event','summary':'Meeting','iCalUID':'shared',
               'start':{'dateTime':'2026-09-08T12:00:00Z'},'end':{'dateTime':'2026-09-08T13:00:00Z'}}
        with patch.object(google,'keyring',return_value={}), patch.object(google,'request_json',return_value={'access_token':'fake'}), patch.object(google,'list_all',side_effect=[[{'id':'same','summary':'Work','backgroundColor':'invalid'}],[event]]):
            calendars, events=google.fetch_account({'id':'a','email':'a@example.com'},datetime.now(timezone.utc),timezone.utc)
        self.assertEqual(calendars[0]['id'],'a:same')
        self.assertEqual(events[0]['calendarId'],'a:same')
        self.assertEqual(events[0]['iCalUID'],'shared')
        self.assertEqual(events[0]['color'],'#89b4fa')

if __name__ == '__main__':
    unittest.main()
