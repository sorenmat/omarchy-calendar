# Privacy policy — Calendar & Agenda for Omarchy

Effective date: 8 September 2026

Calendar & Agenda for Omarchy is an open-source desktop calendar plugin maintained by sorenmat. It displays events from the Google accounts and calendars you choose to connect.

## Google data the plugin accesses

With your permission, the plugin accesses your Google account identifier and verified email address, the list of calendars you subscribe to, and events from calendars you can read. Event data includes titles, dates and times, locations, meeting and event links, calendar colours, event types, and your invitation response. Google may return additional fields in an API response; the plugin keeps only the fields needed for its calendar and agenda features.

The plugin requests read-only Calendar access. It does not create, edit, or delete Google Calendar events and does not read Gmail messages.

## How data is used and stored

Data is used to display your month calendar, agenda, upcoming-event countdowns, and meeting actions. Calendar metadata and events are cached on your device so the display remains available between syncs and when a request fails. Account tokens are stored in your desktop's Secret Service keyring. Tokens are sent to Google when authenticating or refreshing access.

At event start, the plugin sends the event title, calendar name, account email, and meeting or event link to your local desktop notification service. Omarchy may retain these in notification history. A local record of hashed event identifiers and start times prevents duplicate alerts; older entries are pruned when subsequent alerts are processed. Removing an account from the plugin does not clear notifications already stored by the desktop.

Your device communicates directly with Google. The maintainer does not operate a server that receives your calendar data or account tokens. The plugin contains no analytics or telemetry and does not sell personal information, use it for advertising, or use it to train AI models.

Calendar & Agenda for Omarchy's use and transfer of information received from Google APIs adheres to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including its Limited Use requirements.

## Sharing and external services

Calendar requests and authentication are processed by Google under [Google's Privacy Policy](https://policies.google.com/privacy). When you open an event or join a meeting, your browser connects to the destination service, which has its own privacy practices. Support information you choose to submit through GitHub is handled by GitHub under its privacy policy.

## Retention and deletion

The current implementation synchronizes events from the past 31 days through the next 93 days. A successful sync replaces the account's prior event cache; a failed sync retains the last successful cache until a later successful sync or removal.

You can hide individual calendars without disconnecting an account. Hiding a calendar changes the display; it does not delete cached data or stop synchronization.

Removing an account in the plugin deletes its saved account token and cached calendar data from the device. You can separately revoke Google's authorization through your [Google Account connections](https://myaccount.google.com/connections). Locally cached data remains until removed through the plugin or deleted from `${XDG_STATE_HOME:-~/.local/state}/smo.calendar`. Removing the plugin alone does not automatically erase this directory or keyring entries.

An imported Desktop OAuth app registration may remain in the keyring after account removal so another account can reuse it. This app registration is separate from the account's private refresh token.

## Contact and changes

For questions about this policy, contact the maintainer through the [project's GitHub issues](https://github.com/sorenmat/omarchy-calendar/issues). Changes to this policy will be published with an updated effective date in this repository.
