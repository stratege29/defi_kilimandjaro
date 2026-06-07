// Appelle la Cloud Function callable `publishPack` SANS navigateur.
//
// Contourne le sign-in Google de l'admin console : on s'authentifie par
// script en tant qu'un compte admin existant via un custom token, qu'on
// échange contre un ID token (qui embarque le claim role=admin du compte),
// puis on appelle la callable publishPack en europe-west1.
//
// AUTH : Application Default Credentials (gcloud auth application-default login)
//        + le compte ciblé doit avoir le custom claim role=admin.
//
// USAGE
//   node tools/scripts/publish_pack.mjs --project kilimandjaro-dev \
//     --email kossea@ultimesgriots.com --pack football_ci
//   # ajoute --apply pour exécuter réellement (sinon dry-run = ne publie pas)

import { parseArgs } from 'node:util';
import process from 'node:process';
import admin from 'firebase-admin';

const { values } = parseArgs({
  options: {
    project: { type: 'string' },
    email: { type: 'string' },
    pack: { type: 'string', default: 'football_ci' },
    apiKey: { type: 'string' },
    region: { type: 'string', default: 'europe-west1' },
    serviceAccountId: { type: 'string' },
    apply: { type: 'boolean', default: false },
  },
});

if (!values.project || !values.email) {
  console.error(
    'usage: --project <id> --email <admin-email> [--pack football_ci] ' +
      '[--apiKey <web-api-key>] [--apply]',
  );
  process.exit(64);
}

// Clé API web de kilimandjaro-dev (publique, sert juste à l'échange de token).
const WEB_API_KEY =
  values.apiKey ?? 'AIzaSyAbFTn3FiASP2PsjizyWuZfMGs3UBTTz38';

// serviceAccountId : permet à createCustomToken de signer via l'API IAM
// signBlob (sans clé privée locale) en utilisant l'ADC. Défaut = SA App Engine.
const serviceAccountId =
  values.serviceAccountId ?? `${values.project}@appspot.gserviceaccount.com`;
admin.initializeApp({ projectId: values.project, serviceAccountId });

// 1. Résout l'uid + vérifie le claim admin.
const user = await admin.auth().getUserByEmail(values.email);
const role = user.customClaims?.role;
console.log(`Compte : ${values.email} (uid ${user.uid}) role=${role ?? '—'}`);
if (role !== 'admin') {
  console.error(
    `ABORT: ce compte n'a pas role=admin (publishPack le refuserait). ` +
      `Pose-le d'abord : node tools/scripts/set_admin_role.mjs --project ` +
      `${values.project} --email ${values.email} --role admin`,
  );
  process.exit(1);
}

if (!values.apply) {
  console.log(
    `\nDRY-RUN : prêt à publier le pack "${values.pack}" en tant qu'admin.\n` +
      'Relance avec --apply pour exécuter réellement publishPack.',
  );
  process.exit(0);
}

// 2. Custom token -> ID token (l'ID token embarque les custom claims du compte).
const customToken = await admin.auth().createCustomToken(user.uid);
const exchangeRes = await fetch(
  `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${WEB_API_KEY}`,
  {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: customToken, returnSecureToken: true }),
  },
);
const exchangeJson = await exchangeRes.json();
if (!exchangeRes.ok || !exchangeJson.idToken) {
  console.error('Echec échange custom token -> ID token :', exchangeJson);
  process.exit(1);
}
const idToken = exchangeJson.idToken;
console.log('ID token obtenu (claims admin embarqués).');

// 3. Appel callable publishPack (protocole callable v2 : body {data}, Bearer).
const url = `https://${values.region}-${values.project}.cloudfunctions.net/publishPack`;
console.log(`POST ${url}`);
const callRes = await fetch(url, {
  method: 'POST',
  headers: {
    'Content-Type': 'application/json',
    Authorization: `Bearer ${idToken}`,
  },
  body: JSON.stringify({ data: { packId: values.pack } }),
});
const text = await callRes.text();
let parsed;
try {
  parsed = JSON.parse(text);
} catch {
  parsed = text;
}
console.log(`\nHTTP ${callRes.status}`);
console.log(JSON.stringify(parsed, null, 2));

if (callRes.ok && parsed?.result) {
  console.log('\n✅ Publié. Nouvelle version + .gz propre + catalog_version bumpé.');
  process.exit(0);
} else {
  console.error('\n❌ Echec publishPack.');
  process.exit(1);
}
