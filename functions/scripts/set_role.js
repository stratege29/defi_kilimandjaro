/**
 * Pose (ou retire) un rôle backoffice sur un utilisateur Firebase Auth via custom claim.
 *   role: 'admin'     → tout (publish, players, Instagram, claims)
 *         'editor'    → édition contenu (CRUD packs/devinettes), pas de publish
 *         'moderator' → submissions UGC, lecture meta
 *         'none'      → retire le rôle
 *
 * L'utilisateur DOIT s'être connecté au moins une fois au console (Google) pour
 * exister côté Auth. Après pose du claim, il doit se déconnecter/reconnecter
 * (ou attendre ~1h) pour rafraîchir son ID token.
 *
 * Prérequis : gcloud auth application-default login (ADC valide).
 * Usage : node functions/scripts/set_role.js <email> <admin|editor|moderator|none>
 */
const admin = require("firebase-admin");
admin.initializeApp({ projectId: "kilimandjaro-dev" });

const [, , email, role] = process.argv;
const ROLES = new Set(["admin", "editor", "moderator", "none"]);

(async () => {
  if (!email || !ROLES.has(role)) {
    console.error("Usage: node functions/scripts/set_role.js <email> <admin|editor|moderator|none>");
    process.exit(1);
  }
  const auth = admin.auth();
  let user;
  try {
    user = await auth.getUserByEmail(email);
  } catch (e) {
    console.error(`Utilisateur introuvable côté Auth : ${email} (${e.code})`);
    console.error("→ Il doit d'abord se connecter UNE fois au console (Google sign-in), puis relancer ce script.");
    process.exit(2);
  }
  const claims = role === "none" ? {} : { role };
  await auth.setCustomUserClaims(user.uid, claims);
  console.log(`OK · ${email} (uid ${user.uid}) → claims ${JSON.stringify(claims)}`);
  console.log("→ L'utilisateur doit se déconnecter/reconnecter (ou attendre ~1h) pour rafraîchir le token.");
})().catch((e) => { console.error("ERR", e.message); process.exit(1); });
