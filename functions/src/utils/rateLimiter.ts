import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

/**
 * Rate-limiter à fenêtre journalière (UTC) basé sur Firestore.
 * Documents `users_quota/{uid}` ou `ip_quota/{ipHash}`.
 *
 * `maxPerDay = 0` désactive (utile pour les comptes admin).
 */
export interface QuotaCheckResult {
  allowed: boolean;
  count: number;
  remaining: number;
}

function dayBucket(now: Date): string {
  return now.toISOString().slice(0, 10);
}

export async function checkAndIncrement(
  collection: "users_quota" | "ip_quota",
  key: string,
  maxPerDay: number
): Promise<QuotaCheckResult> {
  if (maxPerDay <= 0) {
    return { allowed: true, count: 0, remaining: Number.MAX_SAFE_INTEGER };
  }

  const ref = getFirestore().collection(collection).doc(key);
  const now = new Date();
  const bucket = dayBucket(now);

  return getFirestore().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    const sameBucket = data?.dayBucket === bucket;
    const currentCount: number = sameBucket ? Number(data?.count ?? 0) : 0;

    if (currentCount >= maxPerDay) {
      return {
        allowed: false,
        count: currentCount,
        remaining: 0,
      };
    }

    tx.set(
      ref,
      {
        dayBucket: bucket,
        count: sameBucket ? FieldValue.increment(1) : 1,
        lastAt: Timestamp.fromDate(now),
      },
      { merge: true }
    );

    return {
      allowed: true,
      count: currentCount + 1,
      remaining: maxPerDay - currentCount - 1,
    };
  });
}
