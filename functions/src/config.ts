/** Region every function runs in. Must match AppConfig.functionsRegion in the app. */
export const REGION = 'us-central1';

/** Time zone used for due dates, the monthly generator and reminders. */
export const TIME_ZONE = 'Asia/Qatar';

/** Host that serves invite links: https://<host>/j/<token>. */
export function inviteHost(): string {
  if (process.env.INVITE_HOST) return process.env.INVITE_HOST;
  const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || 'split-up-cd996';
  return `${project}.web.app`;
}

export const APP_NAME = 'SplitRoom';

/** Supported currencies and how many decimals their minor unit has. */
export const CURRENCIES: Record<string, number> = {
  QAR: 2, AED: 2, SAR: 2, KWD: 3, BHD: 3, OMR: 3,
  USD: 2, EUR: 2, GBP: 2, INR: 2, PKR: 2, BDT: 2,
  LKR: 2, NPR: 2, PHP: 2, EGP: 2, JPY: 0,
};

export const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no 0/O/1/I
export const CODE_LENGTH = 6;

export const PAYMENT_METHODS = ['cash', 'bank_transfer', 'other'];
