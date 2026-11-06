# CampusHub — Features Added & Bugs Fixed

*31 Oct – 1 Nov 2026*

This round added in-app messaging (future plan §1.1) and worked through several rounds of bug
reports. Everything was tested locally (FastAPI on :8000, Flutter web on :8081); nothing was
deployed. Database revision 8 → 11 (migrations `008`–`011`).

## New features

### In-app messaging (Buy & Sell and Lost & Found)

- **One chat per person**, like WhatsApp. Each thing discussed with that person (a listing, a lost
  report, a found report) is a *topic* inside the chat. An item card marks where talk about it
  starts, chips under the header filter to one item, and an "About: …" selector above the message
  box says what the next message is about. Messages with no topic are general chat.
- **Starting a chat:** "Message" on every listing card, "Message seller" on a listing, and
  "Message the owner / finder" on Lost & Found posts. A second item from the same person joins
  the existing chat.
- **Offers** belong to one listing. The other person accepts or declines. **Accepting reserves the
  listing automatically.**
- **Other features:** read receipts ("Seen"), unsend for everyone, block / unblock, unread badges
  (app bar and account menu → "My messages"), notifications that never contain message text,
  and a send limit of 30 messages a minute.
- **Encryption, and what it does *not* give yet:**
  - Messages are encrypted in the app (X25519 + AES-256-GCM).
  - The first version locked each key with a passphrase. That was removed because it was
    impractical, and the server now stores each key, so **the server can read chats today**.
  - True end-to-end encryption (passkey + QR device linking) is planned in
    `future-plan-2026-10-31-next-level-features.md` §1.1.
- **Merging old chats:** the per-listing chats from before revision 10 were merged per person
  (migration `010`). Their old messages still decrypt.
- **Delivery:** messages are fetched by polling every 3 s. Instant delivery needs WebSockets (see
  the cloud checklist).

### Notifications

- Remove one (×), select several and delete them, or "Clear all".
- "Saved searches" moved out of the notifications window into the account menu.

### Profile

- The email is shown (read-only) in the edit form.
- The phone number has a country picker (India by default) with per-country length checks.
- A new number must be verified with a 6-digit code (`POST /me/phone/code` and `/verify`). There
  is no SMS provider yet, so the code is logged.

### Filters

- Buy & Sell and Lost & Found use one **Filters** button.
- It opens a panel (side panel on desktop, bottom sheet on phones) with Category, Price / When,
  Status and Sort.
- Changes apply on "Show results". Active filters appear as removable chips.

### Smaller changes

- Moderators use `/moderator`, and admins use `/admin`.
- Profile and moderator pages keep their own URLs, so a refresh no longer goes back to `/buy`.
- Tab switches and opening a chat no longer animate (they used to jitter).
- Default filters: Buy & Sell shows Available + Reserved; Lost & Found shows Open.
- Lost & Found no longer has a "Matched" status (migration `011`).
- The refresh button was removed from the top bar.
- Two items with the same title in one chat are labelled with when they were first discussed.

## Bugs fixed

| Bug | Cause | Fix |
| --- | --- | --- |
| A removed moderator still saw the moderation tools | The app only loaded roles at sign-in and reused the saved copy afterwards. The server was always safe: it checks rights on every request. | The app re-checks `/me` on start, on returning to the tab, every minute, after any 403, and when the moderator page opens. |
| Guests' API calls were sent as the configured dev user | The API client fell back to the default `X-Dev-User` with no session | It sends an identity only when signed in. |
| "X hasn't set up secure messaging" blocked new chats | A person had no key until they opened Messages | The server creates a key when a chat is opened. |
| Opening a chat from a listing went back to the listing | The dialog's browser-history cleanup undid the navigation | It waits for the dialog to finish closing. |
| A new tab sometimes asked to sign in again | Not reproduced; the session is in localStorage, which all tabs share | Session restore re-reads storage and checks it with the server; sign-in and sign-out sync across tabs. |

## Tests

- **Backend:** 125 passing. New suites cover messaging (`tests/test_chat.py`, with a Python
  reference implementation of the encryption in `tests/chat_crypto.py`), notification deletion,
  phone verification and the removed "matched" status.
- **Flutter:** 69 passing. New tests cover message encryption (byte-for-byte against the Python
  version), chat models, phone countries and the filter panel.
- **Flutter:** 14 tests were already failing before this work and still fail.
