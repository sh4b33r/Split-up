// End-to-end test of the backend against the Firebase emulators.
// Run with:  npm run test:e2e
//
// It signs up real (emulated) users, calls the deployed-shape callables over
// HTTP exactly as the app does, and checks what ends up in Firestore.
import assert from 'node:assert/strict';
import { before, test } from 'node:test';
import { getAuth } from 'firebase-admin/auth';
import { runRecurring, runReminders } from '../../src/scheduled';
import { addDays, db, today } from '../../src/util';

const PROJECT = process.env.GCLOUD_PROJECT ?? 'demo-splitup';
const AUTH = `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST ?? '127.0.0.1:9099'}`;
const FN = `http://127.0.0.1:5001/${PROJECT}/us-central1`;

interface User { uid: string; email: string; token: string }

async function authCall(path: string, body: unknown): Promise<any> {
  const res = await fetch(`${AUTH}/identitytoolkit.googleapis.com/v1/accounts:${path}?key=fake`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const json: any = await res.json();
  if (!res.ok) throw new Error(JSON.stringify(json));
  return json;
}

async function call(user: User, fn: string, data: unknown): Promise<any> {
  const res = await fetch(`${FN}/${fn}`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', authorization: `Bearer ${user.token}` },
    body: JSON.stringify({ data }),
  });
  const json: any = await res.json();
  if (json.error) {
    const err: any = new Error(json.error.message);
    err.status = json.error.status;
    throw err;
  }
  return json.result;
}

async function signUp(email: string, name: string): Promise<User> {
  const r = await authCall('signUp', { email, password: 'secret123', returnSecureToken: true });
  const user = { uid: r.localId as string, email, token: r.idToken as string };
  await call(user, 'updateProfile', { name });
  return user;
}

async function fails(p: Promise<unknown>, status: string, message?: RegExp) {
  await assert.rejects(p, (e: any) => {
    assert.equal(e.status, status, `expected ${status}, got ${e.status}: ${e.message}`);
    if (message) assert.match(e.message, message);
    return true;
  });
}

const net = async (roomId: string, u: User) =>
  (await db.doc(`rooms/${roomId}/members/${u.uid}`).get()).data()!.netMinor as number;
const share = async (roomId: string, splitId: string, u: User) =>
  (await db.doc(`rooms/${roomId}/splits/${splitId}/shares/${u.uid}`).get()).data()!;
const split = async (roomId: string, splitId: string) =>
  (await db.doc(`rooms/${roomId}/splits/${splitId}`).get()).data()!;
const inbox = async (u: User, type: string) =>
  (await db.collection(`users/${u.uid}/notifications`).where('type', '==', type).get()).docs.map((d) => d.data());

/** Recomputes every balance from the shares and compares it with the cached netMinor. */
async function assertBalances(roomId: string) {
  const expected = new Map<string, number>();
  const splits = await db.collection(`rooms/${roomId}/splits`).get();
  for (const s of splits.docs) {
    const shares = await s.ref.collection('shares').get();
    for (const sh of shares.docs) {
      const d = sh.data();
      if (d.status === 'paid') continue;
      expected.set(d.userId, (expected.get(d.userId) ?? 0) - d.amountMinor);
      expected.set(d.payerId, (expected.get(d.payerId) ?? 0) + d.amountMinor);
    }
  }
  const members = await db.collection(`rooms/${roomId}/members`).get();
  let sum = 0;
  for (const m of members.docs) {
    assert.equal(m.data().netMinor, expected.get(m.id) ?? 0, `netMinor of ${m.data().displayName}`);
    sum += m.data().netMinor;
  }
  assert.equal(sum, 0, 'balances in a room always sum to zero');
}

const stamp = Date.now();
let aj: User, rahul: User, sara: User;
let roomId: string, code: string, token: string;
let rent: string, internet: string;

before(async () => {
  aj = await signUp(`aj${stamp}@example.com`, 'Aj');
  rahul = await signUp(`rahul${stamp}@example.com`, 'Rahul');
  sara = await signUp(`sara${stamp}@example.com`, 'Sara');
});

test('create a room: owner, unambiguous 6-character code, invite token', async () => {
  const r = await call(aj, 'createRoom', { name: 'Flat 12', currency: 'QAR', icon: '🏠' });
  roomId = r.roomId;
  code = r.code;
  assert.match(code, /^[A-HJ-NP-Z2-9]{6}$/);
  const room = (await db.doc(`rooms/${roomId}`).get()).data()!;
  token = room.inviteToken;
  assert.equal(room.ownerId, aj.uid);
  assert.deepEqual(room.memberIds, [aj.uid]);
  assert.equal((await db.doc(`roomCodes/${code}`).get()).data()!.roomId, roomId);
  assert.equal((await db.doc(`rooms/${roomId}/members/${aj.uid}`).get()).data()!.role, 'owner');
  await fails(call(aj, 'createRoom', { name: '', currency: 'QAR' }), 'INVALID_ARGUMENT');
  await fails(call(aj, 'createRoom', { name: 'X', currency: 'ZZZ' }), 'INVALID_ARGUMENT');
});

test('join by code: preview first, then join', async () => {
  const p = await call(rahul, 'previewRoom', { codeOrToken: code.toLowerCase() });
  assert.equal(p.name, 'Flat 12');
  assert.equal(p.ownerName, 'Aj');
  assert.equal(p.memberCount, 1);
  assert.equal(p.alreadyMember, false);
  assert.equal((await call(rahul, 'joinRoom', { codeOrToken: code })).status, 'joined');
  assert.equal((await call(rahul, 'joinRoom', { codeOrToken: code })).status, 'already');
  await fails(call(rahul, 'joinRoom', { codeOrToken: 'ZZZZZZ' }), 'NOT_FOUND');
});

test('join by link with approval on: request, then the owner approves', async () => {
  await fails(call(rahul, 'updateRoom', { roomId, requireApproval: true }), 'PERMISSION_DENIED');
  await call(aj, 'updateRoom', { roomId, requireApproval: true });
  assert.equal((await call(sara, 'joinRoom', { codeOrToken: token })).status, 'requested');
  assert.equal((await inbox(aj, 'join_request')).length, 1);
  await fails(call(rahul, 'respondJoinRequest', { roomId, uid: sara.uid, approve: true }), 'PERMISSION_DENIED');
  await call(aj, 'respondJoinRequest', { roomId, uid: sara.uid, approve: true });
  const room = (await db.doc(`rooms/${roomId}`).get()).data()!;
  assert.deepEqual(room.memberIds, [aj.uid, rahul.uid, sara.uid]);
  assert.equal((await inbox(sara, 'join_approved')).length, 1);
  await call(aj, 'updateRoom', { roomId, requireApproval: false });
});

test('add a split: rent 3,000 equally, payer share is already Paid', async () => {
  const everyone = [aj, rahul, sara].map((u) => ({ uid: u.uid }));
  rent = (await call(aj, 'createSplit', {
    roomId, title: 'Rent', totalMinor: 300000, paidBy: aj.uid, splitType: 'equal',
    participants: everyone, dueDate: addDays(today(), 2),
  })).splitId;
  assert.equal((await share(roomId, rent, aj)).status, 'paid');
  assert.equal((await share(roomId, rent, rahul)).status, 'unpaid');
  assert.equal((await share(roomId, rent, rahul)).amountMinor, 100000);
  assert.equal(await net(roomId, aj), 200000);
  assert.equal(await net(roomId, rahul), -100000);
  const n = await inbox(rahul, 'split_created');
  assert.equal(n.length, 1);
  assert.equal(n[0].title, 'New split: Rent');
  assert.match(n[0].body, /^You owe 1,000 QAR to Aj, due \d+ \w{3}$/);
  assert.equal((await inbox(aj, 'split_created')).length, 0, 'the creator is not notified');

  internet = (await call(rahul, 'createSplit', {
    roomId, title: 'Internet', totalMinor: 10000, paidBy: aj.uid, splitType: 'equal', participants: everyone,
  })).splitId;
  assert.equal((await share(roomId, internet, aj)).amountMinor, 3334);
  assert.equal((await share(roomId, internet, rahul)).amountMinor, 3333);
  assert.equal((await share(roomId, internet, sara)).amountMinor, 3333);
  await assertBalances(roomId);
});

test('split validation is enforced on the server', async () => {
  const base = { roomId, title: 'Dinner', totalMinor: 10000, paidBy: aj.uid };
  await fails(call(aj, 'createSplit', {
    ...base, splitType: 'exact', participants: [{ uid: aj.uid, value: 5000 }, { uid: rahul.uid, value: 4000 }],
  }), 'INVALID_ARGUMENT', /add up to the total/);
  await fails(call(aj, 'createSplit', { ...base, splitType: 'equal', participants: [{ uid: aj.uid }] }),
    'FAILED_PRECONDITION', /other than whoever paid/);
  await fails(call(aj, 'createSplit', { ...base, splitType: 'equal', participants: [{ uid: 'stranger' }] }),
    'FAILED_PRECONDITION');
  await fails(call(aj, 'createSplit', { ...base, totalMinor: 99.5, splitType: 'equal', participants: [{ uid: rahul.uid }] }),
    'INVALID_ARGUMENT');
  const outsider = await signUp(`out${stamp}@example.com`, 'Outsider');
  await fails(call(outsider, 'createSplit', { ...base, splitType: 'equal', participants: [{ uid: rahul.uid }] }),
    'PERMISSION_DENIED');
  await fails(call(outsider, 'markPaidDirect', { roomId, splitId: rent, uid: rahul.uid }), 'PERMISSION_DENIED');
});

test('pay and confirm: I\'ve paid -> reject -> I\'ve paid -> confirm', async () => {
  await fails(call(rahul, 'markPaid', { roomId, splitId: rent, method: 'bitcoin' }), 'INVALID_ARGUMENT');
  await call(rahul, 'markPaid', { roomId, splitId: rent, method: 'bank_transfer', note: 'sent' });
  assert.equal((await share(roomId, rent, rahul)).status, 'marked_paid');
  assert.equal(await net(roomId, rahul), -100000 - 3333, 'marked paid still counts as unpaid');
  assert.match((await inbox(aj, 'share_marked'))[0].body, /^Rahul marked 1,000 QAR as paid\. Confirm\?$/);
  await fails(call(rahul, 'markPaid', { roomId, splitId: rent, method: 'cash' }), 'FAILED_PRECONDITION');

  // A plain participant cannot confirm, not even their own share.
  await fails(call(sara, 'confirmShare', { roomId, splitId: rent, uid: rahul.uid }), 'PERMISSION_DENIED');
  await fails(call(rahul, 'confirmShare', { roomId, splitId: rent, uid: rahul.uid }), 'PERMISSION_DENIED');

  await call(aj, 'rejectShare', { roomId, splitId: rent, uid: rahul.uid, reason: 'not received yet' });
  const rejected = await share(roomId, rent, rahul);
  assert.equal(rejected.status, 'unpaid');
  assert.equal(rejected.rejectReason, 'not received yet');
  assert.match((await inbox(rahul, 'share_rejected'))[0].body, /rejected your payment: "not received yet"/);

  await call(rahul, 'markPaid', { roomId, splitId: rent, method: 'cash' });
  const r = await call(aj, 'confirmShare', { roomId, splitId: rent, uid: rahul.uid });
  assert.equal(r.settled, false);
  assert.equal((await share(roomId, rent, rahul)).status, 'paid');
  assert.equal(await net(roomId, rahul), -3333);
  assert.equal((await split(roomId, rent)).shareSummary[rahul.uid].status, 'paid');
  await fails(call(aj, 'confirmShare', { roomId, splitId: rent, uid: rahul.uid }), 'FAILED_PRECONDITION', /already paid/);
  await assertBalances(roomId);
});

test('two confirmations at once: exactly one wins', async () => {
  await call(sara, 'markPaid', { roomId, splitId: internet, method: 'cash' });
  const results = await Promise.allSettled([
    call(aj, 'confirmShare', { roomId, splitId: internet, uid: sara.uid }),
    call(aj, 'confirmShare', { roomId, splitId: internet, uid: sara.uid }),
  ]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  await assertBalances(roomId);
});

test('mark paid directly settles the split; undo reopens it', async () => {
  await fails(call(sara, 'markPaidDirect', { roomId, splitId: rent, uid: sara.uid }), 'PERMISSION_DENIED');
  const r = await call(aj, 'markPaidDirect', { roomId, splitId: rent, uid: sara.uid });
  assert.equal(r.settled, true);
  assert.equal((await split(roomId, rent)).status, 'settled');
  assert.equal((await inbox(aj, 'split_settled')).length, 1);
  assert.match((await inbox(sara, 'share_paid_direct'))[0].body, /^Aj marked your Rent share as paid$/);

  await fails(call(sara, 'undoPaid', { roomId, splitId: rent, uid: sara.uid }), 'PERMISSION_DENIED');
  await fails(call(aj, 'undoPaid', { roomId, splitId: rent, uid: aj.uid }), 'INVALID_ARGUMENT');
  await call(aj, 'undoPaid', { roomId, splitId: rent, uid: sara.uid });
  assert.equal((await split(roomId, rent)).status, 'open');
  assert.equal((await share(roomId, rent, sara)).status, 'unpaid');
  await assertBalances(roomId);
});

test('edit and delete rules', async () => {
  const everyone = [aj, rahul, sara].map((u) => ({ uid: u.uid }));
  const dueDate = addDays(today(), 2);
  const edit = { roomId, splitId: rent, title: 'Rent', paidBy: aj.uid, splitType: 'equal', participants: everyone, dueDate };
  // Rahul has paid: amounts are locked, the title is not.
  await fails(call(aj, 'updateSplit', { ...edit, totalMinor: 330000 }), 'FAILED_PRECONDITION', /Undo the paid shares/);
  await fails(call(rahul, 'updateSplit', { ...edit, totalMinor: 300000, title: 'Rent!' }), 'PERMISSION_DENIED');
  await call(aj, 'updateSplit', { ...edit, totalMinor: 300000, title: 'House rent' });
  assert.equal((await split(roomId, rent)).title, 'House rent');
  assert.equal((await share(roomId, rent, rahul)).status, 'paid', 'a title edit keeps paid shares paid');
  await fails(call(aj, 'deleteSplit', { roomId, splitId: rent }), 'FAILED_PRECONDITION');

  // A split nobody has paid can be changed freely by its creator.
  const gas = (await call(rahul, 'createSplit', {
    roomId, title: 'Gas', totalMinor: 9000, paidBy: rahul.uid, splitType: 'equal', participants: everyone,
  })).splitId;
  await fails(call(sara, 'updateSplit', { ...edit, splitId: gas, totalMinor: 12000, paidBy: rahul.uid }), 'PERMISSION_DENIED');
  await call(rahul, 'updateSplit', {
    roomId, splitId: gas, title: 'Gas', totalMinor: 12000, paidBy: rahul.uid, splitType: 'shares',
    participants: [{ uid: aj.uid, value: 2 }, { uid: rahul.uid, value: 1 }],
  });
  assert.equal((await share(roomId, gas, aj)).amountMinor, 8000);
  assert.equal((await db.doc(`rooms/${roomId}/splits/${gas}/shares/${sara.uid}`).get()).exists, false);
  assert.match((await inbox(aj, 'split_updated')).at(-1)!.body, /you now owe 80 QAR/);
  await assertBalances(roomId);
  await fails(call(sara, 'deleteSplit', { roomId, splitId: gas }), 'PERMISSION_DENIED');
  await call(rahul, 'deleteSplit', { roomId, splitId: gas });
  assert.equal((await db.doc(`rooms/${roomId}/splits/${gas}`).get()).exists, false);
  await assertBalances(roomId);
});

test('monthly bill: one split per month even when the job runs twice', async () => {
  const r = await call(aj, 'createSplit', {
    roomId, title: 'Wifi', totalMinor: 30000, paidBy: aj.uid, splitType: 'equal',
    participants: [aj, rahul, sara].map((u) => ({ uid: u.uid })),
    repeat: { dayOfMonth: 1, dueAfterDays: 4 },
  });
  const period = today().slice(0, 7);
  assert.equal(r.splitId, `${r.ruleId}_${period}`);
  assert.equal((await split(roomId, r.splitId)).periodKey, period);

  // Nothing more this month.
  assert.equal(await runRecurring(today()), 0);

  const nextPeriod = (p: string) => {
    const [y, m] = p.split('-').map(Number);
    return m === 12 ? `${y + 1}-01` : `${y}-${String(m + 1).padStart(2, '0')}`;
  };
  const next = nextPeriod(period);
  assert.equal(await runRecurring(`${next}-01`), 1);
  assert.equal(await runRecurring(`${next}-01`), 0, 'a rerun creates nothing');
  assert.equal(await runRecurring(`${next}-02`), 0);
  const generated = await split(roomId, `${r.ruleId}_${next}`);
  assert.equal(generated.dueDate, `${next}-05`);
  assert.equal(generated.status, 'open');
  assert.equal((await share(roomId, `${r.ruleId}_${next}`, rahul)).status, 'unpaid');
  assert.equal((await share(roomId, r.splitId, rahul)).status, 'unpaid', 'each month is its own split');
  assert.ok((await inbox(rahul, 'split_created')).some((n) => n.title.startsWith('New split: Wifi · ')));

  await fails(call(sara, 'updateRule', { roomId, ruleId: r.ruleId, active: false }), 'PERMISSION_DENIED');
  await call(aj, 'updateRule', { roomId, ruleId: r.ruleId, active: false });
  assert.equal(await runRecurring(`${nextPeriod(next)}-01`), 0, 'a paused rule creates nothing');
  await assertBalances(roomId);
});

test('reminders: 2 days before, on the day, every 3 days overdue', async () => {
  const due = (await split(roomId, rent)).dueDate as string; // today + 2, Sara still unpaid
  const count = async (d: string) => {
    const before = (await inbox(sara, 'reminder')).length + (await inbox(sara, 'overdue')).length;
    await runReminders(d);
    return (await inbox(sara, 'reminder')).length + (await inbox(sara, 'overdue')).length - before;
  };
  assert.ok((await count(addDays(due, -2))) >= 1, 'due in 2 days');
  assert.ok((await count(due)) >= 1, 'due today');
  assert.ok((await count(addDays(due, 3))) >= 1, 'overdue by 3 days');
  const rentReminders = (await inbox(sara, 'overdue')).filter((n) => n.splitId === rent);
  assert.match(rentReminders[0].body, /^House rent was due on \d+ \w{3}: 1,000 QAR to Aj$/);
});

test('leaving: blocked while unsettled; the owner must transfer first', async () => {
  await fails(call(rahul, 'leaveRoom', { roomId }), 'FAILED_PRECONDITION', /unpaid share/);
  await fails(call(aj, 'leaveRoom', { roomId }), 'FAILED_PRECONDITION', /Transfer ownership/);
  await fails(call(aj, 'removeMember', { roomId, uid: sara.uid }), 'FAILED_PRECONDITION');
  await fails(call(rahul, 'removeMember', { roomId, uid: sara.uid }), 'PERMISSION_DENIED');
});

test('invite by email: waits for sign-up, needs a verified address', async () => {
  const email = `Newbie${stamp}@Example.com`;
  await fails(call(rahul, 'inviteByEmail', { roomId, email }), 'PERMISSION_DENIED');
  const r = await call(aj, 'inviteByEmail', { roomId, email });
  assert.equal(r.registered, false);
  const mail = await db.collection('mail').where('to', 'array-contains', email.toLowerCase()).get();
  assert.equal(mail.size, 1);
  assert.ok(mail.docs[0].data().message.text.includes(`/j/${token}`));

  let newbie = await signUp(email.toLowerCase(), 'Newbie');
  assert.match((await inbox(newbie, 'invite'))[0].body, /^Aj invited you to "Flat 12"$/, 'the waiting invite shows up on sign-up');
  const invites = await db.collection('invites').where('emailLower', '==', email.toLowerCase()).get();
  assert.equal(invites.size, 1);
  const inviteId = invites.docs[0].id;
  await fails(call(sara, 'respondInvite', { inviteId, accept: true }), 'PERMISSION_DENIED');
  await fails(call(newbie, 'respondInvite', { inviteId, accept: true }), 'FAILED_PRECONDITION', /Verify your email/);

  await getAuth().updateUser(newbie.uid, { emailVerified: true });
  const again = await authCall('signInWithPassword', { email: newbie.email, password: 'secret123', returnSecureToken: true });
  newbie = { ...newbie, token: again.idToken };
  assert.equal((await call(newbie, 'respondInvite', { inviteId, accept: true })).roomId, roomId);
  const room = (await db.doc(`rooms/${roomId}`).get()).data()!;
  assert.ok(room.memberIds.includes(newbie.uid));
  assert.equal(invites.docs[0].ref.id, inviteId);
  assert.equal((await invites.docs[0].ref.get()).data()!.status, 'accepted');

  // Someone with no shares can leave straight away.
  await call(newbie, 'leaveRoom', { roomId });
  assert.equal((await db.doc(`rooms/${roomId}/members/${newbie.uid}`).get()).data()!.status, 'left');
});

test('an existing user invited by email gets an in-app invite', async () => {
  const dana = await signUp(`dana${stamp}@example.com`, 'Dana');
  const r = await call(aj, 'inviteByEmail', { roomId, email: dana.email });
  assert.equal(r.registered, true);
  assert.match((await inbox(dana, 'invite'))[0].body, /^Aj invited you to "Flat 12"$/);
});

test('roles and ownership', async () => {
  await fails(call(rahul, 'setRole', { roomId, uid: sara.uid, role: 'admin' }), 'PERMISSION_DENIED');
  await call(aj, 'setRole', { roomId, uid: rahul.uid, role: 'admin' });
  await call(rahul, 'updateRoom', { roomId, name: 'Flat 12B' }); // admins can manage
  await call(aj, 'transferOwnership', { roomId, uid: sara.uid });
  const room = (await db.doc(`rooms/${roomId}`).get()).data()!;
  assert.equal(room.ownerId, sara.uid);
  assert.ok(room.adminIds.includes(aj.uid));
  assert.equal((await db.doc(`rooms/${roomId}/members/${sara.uid}`).get()).data()!.role, 'owner');
});

test('reset invite: the old code and link stop working', async () => {
  const r = await call(sara, 'resetInvite', { roomId });
  assert.notEqual(r.code, code);
  const stranger = await signUp(`stranger${stamp}@example.com`, 'Stranger');
  await fails(call(stranger, 'previewRoom', { codeOrToken: code }), 'NOT_FOUND');
  await fails(call(stranger, 'joinRoom', { codeOrToken: token }), 'NOT_FOUND');
  assert.equal((await call(stranger, 'previewRoom', { codeOrToken: r.code })).name, 'Flat 12B');
});

test('profile changes reach every room', async () => {
  await call(rahul, 'updateProfile', { name: 'Rahul K', phone: '+974 5555 0000' });
  assert.equal((await db.doc(`rooms/${roomId}/members/${rahul.uid}`).get()).data()!.displayName, 'Rahul K');
  assert.equal((await db.doc(`users/${rahul.uid}`).get()).data()!.emailLower, rahul.email);
});

test('unauthenticated calls are refused', async () => {
  const res = await fetch(`${FN}/createRoom`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ data: { name: 'x' } }),
  });
  assert.equal(((await res.json()) as any).error.status, 'UNAUTHENTICATED');
});
