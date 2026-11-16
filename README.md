# SplitRoom

Share a room, split the bills, see who owes whom.

A group joins a room (by 6-character code, invite link or email), adds bills,
and tracks each person's share from **Unpaid → Marked paid → Paid**. Monthly
bills like rent repeat automatically, with reminders before and after the due
date.

- **App:** Flutter + GetX (Android, iOS, web)
- **Backend:** Firebase — Auth, Firestore, Cloud Functions (TypeScript), Storage, Cloud Messaging
- **Firebase project:** `split-up-cd996`

## What's in it

| Area | Features |
| --- | --- |
| Account | Email + password, Google, Apple; profile name, photo, phone; email verification |
| Rooms | Create (name, currency, icon); unique code without look-alike characters; share invite link; invite by email (waits for people who haven't signed up); approve new members; admins; transfer ownership; remove, leave; reset code and link |
| Splits | Equal, exact amounts, percentages, shares (2:1:1) with a live per-person preview; paid by anyone; due date; note; receipt photo; edit and delete with the permission rules below |
| Payments | "I've paid" with method, note and proof photo; payer confirms or rejects with a reason; mark paid directly for cash; undo; split shows Settled when everyone has paid |
| Monthly bills | Repeat on day 1–28 or the last day, due N days later, optional end month; pause, resume, end; a re-run of the job never creates a duplicate |
| Reminders | 2 days before, on the due date, then every 3 days while overdue |
| Balances | Net balance per member in every room; "You owe" / "You're owed" totals across all rooms on Home |
| Log | Room activity log and per-split history |
| Notifications | Push (FCM) plus an in-app inbox; tapping opens the split |

**Money is never a floating-point number.** Every amount is an integer in minor
units (1 QAR = 100 dirhams). Rounding leftovers go one unit at a time to the
first people in the list, so shares always add up to the total exactly.
`lib/core/utils/split_calculator.dart` and `functions/src/calc.ts` are the same
algorithm with the same tests.

**The app never writes money or membership.** Every change goes through a
Cloud Function that re-checks permissions and the current status inside a
transaction. Firestore rules make those documents read-only to clients.

### Who can do what

| Action | Room owner / admin | Split creator | Payer | Participant |
| --- | --- | --- | --- | --- |
| Rename room, invite, remove members, reset code | Yes | No | No | No |
| Add a split | Yes | Yes | Yes | Yes |
| Edit or delete a split nobody has paid | Yes | Yes | No | No |
| Edit a split after someone paid (title, date, note only) | Yes | No | No | No |
| Tap "I've paid" on own share | Yes | Yes | n/a | Yes |
| Confirm or reject a Marked paid share | Yes | Yes | Yes | No |
| Mark any share paid directly | Yes | Yes | Yes | No |
| Undo a paid share | Yes | Yes | No | No |

## Project layout

```
lib/
  main.dart                  start-up, emulator switch
  firebase_options.dart      PLACEHOLDER: generate with flutterfire configure
  app/                       config, routes, theme, start-up bindings
  core/
    services/                api (Cloud Functions), auth, push, deep links, storage
    utils/                   money, split_calculator, dates, ui helpers
    widgets/                 avatar, status chip, amount field, empty state...
  data/                      models and live Firestore queries
  modules/                   one folder per screen (controller + view)
functions/
  src/                       rooms, invites, splits, shares, scheduled, notify
  test/unit                  calculator tests
  test/e2e                   end-to-end tests against the emulators
firestore.rules  storage.rules  firestore.indexes.json  firebase.json
```

## Run it locally (no Firebase setup needed)

Needs Flutter 3.47+, Node 22 and the Firebase CLI (`npm i -g firebase-tools`).

```bash
cd functions && npm install && npm run build && cd ..
```

```bash
firebase emulators:start --project demo-splitup
```

In a second terminal:

```bash
flutter run --dart-define=USE_EMULATOR=true
```

On an Android emulator the app reaches the emulators at `10.0.2.2`
automatically. On a real phone, pass your computer's IP:
`--dart-define=EMULATOR_HOST=192.168.1.20`. The emulator UI at
http://localhost:4000 shows the data. Push notifications don't run against the
emulators; everything still appears in the in-app inbox.

## Tests

```bash
flutter test
```

```bash
cd functions && npm test
```

```bash
cd functions && npm run test:e2e
```

`test:e2e` starts the emulators and runs 18 scenarios through the real
callable functions: joining, approvals, every split type, I've paid → reject →
confirm, two confirmations at once, mark paid directly, undo, edit and delete
rules, monthly bills (including a re-run creating nothing), reminders, leaving,
email invites before and after sign-up, roles, resetting the code, and
rejecting signed-out calls.

## Connect it to the Firebase project

1. **Plan.** Cloud Functions and scheduled jobs need the **Blaze** (pay as you
   go) plan. At small-group scale this normally stays within the free quota.
2. **Authentication → Sign-in method:** enable Email/Password, Google and
   Apple.
3. **Firestore Database:** create it (production mode). Pick a region close to
   your users, for example `me-central1` (Doha) or `europe-west1`.
4. **Storage:** create the default bucket.
5. **Register the apps and generate `lib/firebase_options.dart`:**

   ```bash
   dart pub global activate flutterfire_cli
   ```

   ```bash
   flutterfire configure --project=split-up-cd996
   ```

6. **Deploy rules, indexes and functions:**

   ```bash
   firebase deploy --only firestore,storage,functions
   ```

7. **Invite links and the web app** (Firebase Hosting serves
   `https://split-up-cd996.web.app/j/<token>`):
   - Put your Android signing key's SHA-256 in `web/.well-known/assetlinks.json`
     (`cd android && ./gradlew signingReport`).
   - Put your Apple Team ID in `web/.well-known/apple-app-site-association`, and
     turn on Associated Domains, Push Notifications and Sign in with Apple for
     the app ID in your Apple developer account.

   ```bash
   flutter build web --no-web-resources-cdn
   ```

   ```bash
   firebase deploy --only hosting
   ```

8. **Invite emails:** install the **Trigger Email from Firestore** extension
   with the collection set to `mail` and your SMTP provider (Resend,
   SendGrid...). Without it, email invites still appear in the app for anyone
   who signs up with that address.
9. **Push on iOS:** upload an APNs key under Project settings → Cloud
   Messaging.
10. **Google sign-in on Android:** add your SHA-1 fingerprint to the Android app
    in Project settings.

Before publishing, change the application ID / bundle ID from
`com.example.splitup` to your own (and update it in the two `.well-known`
files).

## Changing things

- Currencies: `Money.currencies` in `lib/core/utils/money.dart` and
  `CURRENCIES` in `functions/src/config.ts` (keep them the same).
- Time zone for due dates, the monthly job (06:00) and reminders (10:00):
  `TIME_ZONE` in `functions/src/config.ts` (default `Asia/Qatar`).
- Functions region: `REGION` in `functions/src/config.ts` and
  `AppConfig.functionsRegion` in `lib/app/app_config.dart`.

## Not built yet (V2 ideas from the plan)

Simplify debts / settle up across splits, skip one month of a monthly bill,
comments on a split, CSV/PDF export, monthly summary email, search and filters.
