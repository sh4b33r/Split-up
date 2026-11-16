import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore, FieldValue, Transaction, WriteBatch } from 'firebase-admin/firestore';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import { CURRENCIES, REGION, TIME_ZONE } from './config';

if (getApps().length === 0) initializeApp();

export const db = getFirestore();
export { FieldValue, HttpsError };

export type Writer = Transaction | WriteBatch;

/** A callable that requires sign-in and hands the handler the caller's uid. */
export function callable<T>(
  handler: (uid: string, data: any, req: CallableRequest) => Promise<T>,
) {
  return onCall({ region: REGION }, async (req) => {
    if (!req.auth) throw new HttpsError('unauthenticated', 'Please sign in first.');
    return handler(req.auth.uid, req.data ?? {}, req);
  });
}

export function bad(message: string): never {
  throw new HttpsError('invalid-argument', message);
}
export function denied(message = 'You are not allowed to do that.'): never {
  throw new HttpsError('permission-denied', message);
}
export function precondition(message: string): never {
  throw new HttpsError('failed-precondition', message);
}
export function notFound(message: string): never {
  throw new HttpsError('not-found', message);
}

// ---- argument validation ---------------------------------------------------

export function str(v: unknown, name: string, max: number, min = 1): string {
  if (typeof v !== 'string') bad(`${name} is required.`);
  const s = (v as string).trim();
  if (s.length < min) bad(`${name} is required.`);
  if (s.length > max) bad(`${name} is too long.`);
  return s;
}
export function optStr(v: unknown, name: string, max: number): string | null {
  if (v === null || v === undefined || v === '') return null;
  return str(v, name, max, 0) || null;
}
export function id(v: unknown, name: string): string {
  if (typeof v !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(v)) bad(`${name} is invalid.`);
  return v as string;
}
export function int(v: unknown, name: string, min: number, max: number): number {
  if (typeof v !== 'number' || !Number.isInteger(v) || v < min || v > max) {
    bad(`${name} is invalid.`);
  }
  return v as number;
}
export function optDate(v: unknown, name: string): string | null {
  if (v === null || v === undefined || v === '') return null;
  if (typeof v !== 'string' || !isValidDate(v)) bad(`${name} is invalid.`);
  return v as string;
}

// ---- dates (plain yyyy-MM-dd strings in the app time zone) -----------------

export function isValidDate(s: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const d = new Date(`${s}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}
export function isValidPeriod(s: string): boolean {
  return /^\d{4}-(0[1-9]|1[0-2])$/.test(s);
}
/** Today's date in the app time zone, as yyyy-MM-dd. */
export function today(now: Date = new Date()): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: TIME_ZONE, year: 'numeric', month: '2-digit', day: '2-digit',
  }).format(now);
}
export function addDays(date: string, days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
export function daysBetween(from: string, to: string): number {
  const a = Date.parse(`${from}T00:00:00Z`);
  const b = Date.parse(`${to}T00:00:00Z`);
  return Math.round((b - a) / 86_400_000);
}
export function lastDayOfMonth(period: string): number {
  const [y, m] = period.split('-').map(Number);
  return new Date(Date.UTC(y, m, 0)).getUTCDate();
}
/** The date a rule runs in `period`. dayOfMonth is 1–28, or -1 for the last day. */
export function runDate(period: string, dayOfMonth: number): string {
  const day = dayOfMonth === -1 ? lastDayOfMonth(period) : dayOfMonth;
  return `${period}-${String(day).padStart(2, '0')}`;
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
/** "2026-12" -> "Dec 2026" */
export function periodLabel(period: string): string {
  const [y, m] = period.split('-').map(Number);
  return `${MONTHS[m - 1]} ${y}`;
}
/** "2026-12-05" -> "5 Dec" */
export function shortDate(date: string): string {
  const [, m, d] = date.split('-').map(Number);
  return `${d} ${MONTHS[m - 1]}`;
}
/** "Rent" + "2026-12" -> "Rent · Dec 2026" */
export function splitLabel(title: string, periodKey?: string | null): string {
  return periodKey ? `${title} · ${periodLabel(periodKey)}` : title;
}

// ---- money -----------------------------------------------------------------

/** 120000, "QAR" -> "1,200 QAR" ; 3334, "QAR" -> "33.34 QAR" */
export function money(minor: number, currency: string): string {
  const decimals = CURRENCIES[currency] ?? 2;
  const scale = 10 ** decimals;
  const neg = minor < 0;
  const abs = Math.abs(minor);
  const whole = Math.floor(abs / scale).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  const frac = abs % scale;
  const fracStr = frac === 0 || decimals === 0 ? '' : `.${String(frac).padStart(decimals, '0')}`;
  return `${neg ? '-' : ''}${whole}${fracStr} ${currency}`;
}

// ---- rooms -----------------------------------------------------------------

export interface Room {
  id: string;
  name: string;
  icon: string;
  currency: string;
  code: string;
  inviteToken: string;
  ownerId: string;
  adminIds: string[];
  memberIds: string[];
  requireApproval: boolean;
}

export const roomRef = (roomId: string) => db.collection('rooms').doc(roomId);
export const memberRef = (roomId: string, uid: string) =>
  roomRef(roomId).collection('members').doc(uid);
export const splitRef = (roomId: string, splitId: string) =>
  roomRef(roomId).collection('splits').doc(splitId);

export function toRoom(snap: FirebaseFirestore.DocumentSnapshot): Room {
  if (!snap.exists) notFound('That room no longer exists.');
  const d = snap.data() as any;
  return {
    id: snap.id,
    name: d.name,
    icon: d.icon,
    currency: d.currency,
    code: d.code,
    inviteToken: d.inviteToken,
    ownerId: d.ownerId,
    adminIds: d.adminIds ?? [],
    memberIds: d.memberIds ?? [],
    requireApproval: d.requireApproval === true,
  };
}

/** Loads a room and checks the caller is a member of it. */
export async function loadRoomFor(uid: string, roomId: string, tx?: Transaction): Promise<Room> {
  const snap = tx ? await tx.get(roomRef(roomId)) : await roomRef(roomId).get();
  const room = toRoom(snap);
  if (!room.memberIds.includes(uid)) denied('You are not a member of this room.');
  return room;
}

/** Owner or admin. */
export function isManager(room: Room, uid: string): boolean {
  return room.ownerId === uid || room.adminIds.includes(uid);
}

/** Display names for members of a room (falls back to "Someone"). */
export async function memberNames(roomId: string, uids: string[]): Promise<Record<string, string>> {
  const unique = [...new Set(uids)];
  const out: Record<string, string> = {};
  if (unique.length === 0) return out;
  const snaps = await db.getAll(...unique.map((u) => memberRef(roomId, u)));
  snaps.forEach((s, i) => {
    out[unique[i]] = (s.data()?.displayName as string) || 'Someone';
  });
  return out;
}

export interface ActivityEntry {
  type: string;
  actorId: string;
  actorName: string;
  splitId?: string | null;
  splitTitle?: string | null;
  targetUserId?: string | null;
  targetName?: string | null;
  amountMinor?: number | null;
  detail?: string | null;
}

/** Appends an entry to the room's activity log as part of `w`. */
export function logActivity(w: Writer, roomId: string, entry: ActivityEntry): void {
  const ref = roomRef(roomId).collection('activity').doc();
  const data = {
    splitId: null,
    splitTitle: null,
    targetUserId: null,
    targetName: null,
    amountMinor: null,
    detail: null,
    ...entry,
    createdAt: FieldValue.serverTimestamp(),
  };
  (w as any).set(ref, data);
}
