// Pose (ou liste) le custom claim `role` sur un compte Firebase Auth.
//
// L'admin console exige `role: 'admin'` pour publier un pack (publishPack →
// requireAdmin). Ce claim se pose hors-bande via l'Admin SDK (la CF
// setUserRole n'existe pas encore).
//
// AUTH : Application Default Credentials (gcloud auth application-default login).
//
// USAGE
//   # Lister les comptes existants (pour trouver le bon email/uid) :
//   node tools/scripts/set_admin_role.mjs --project kilimandjaro-dev --list
//
//   # Poser role=admin sur un compte (par email) :
//   node tools/scripts/set_admin_role.mjs --project kilimandjaro-dev --email toi@gmail.com --role admin
//
// IMPORTANT : le compte doit déjà exister (s'être connecté au moins une fois).
// Après pose du claim, l'utilisateur doit se reconnecter (ou rafraîchir le
// token) pour que le nouveau claim soit pris en compte.

import { parseArgs } from 'node:util';
import process from 'node:process';
import admin from 'firebase-admin';

const { values } = parseArgs({
  options: {
    project: { type: 'string' },
    email: { type: 'string' },
    role: { type: 'string', default: 'admin' },
    list: { type: 'boolean', default: false },
  },
});

if (!values.project) {
  console.error('usage: --project <id> [--list] [--email <email> --role admin]');
  process.exit(64);
}

admin.initializeApp({ projectId: values.project });
const auth = admin.auth();

if (values.list) {
  const res = await auth.listUsers(100);
  console.log(`=== ${res.users.length} comptes (max 100) ===`);
  for (const u of res.users) {
    const role = u.customClaims?.role ?? '—';
    console.log(
      `  ${u.uid}  ${(u.email ?? '(no email)').padEnd(32)}  role=${role}  ` +
        `providers=[${u.providerData.map((p) => p.providerId).join(',')}]`,
    );
  }
  process.exit(0);
}

if (!values.email) {
  console.error('Donne --email <email> (ou --list).');
  process.exit(64);
}

const user = await auth.getUserByEmail(values.email);
const merged = { ...(user.customClaims ?? {}), role: values.role };
await auth.setCustomUserClaims(user.uid, merged);
console.log(
  `OK : ${values.email} (uid ${user.uid}) → role='${values.role}'.\n` +
    'Reconnecte-toi dans l\'admin console pour rafraîchir le token.',
);
process.exit(0);
