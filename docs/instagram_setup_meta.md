# Config compte Meta — Autopilote Instagram (Défi Kilimandjaro)

> État : **compte + app Meta configurés**, token généré. Ce document récapitule la
> configuration retenue et comment renouveler le token. La publication automatique
> tourne en Cloud Function — voir `docs/instagram_cloud_function.md`.

## Configuration retenue (voie « Instagram login »)

- **Compte Instagram** : `@defi_kilimandjaro` (Professionnel / Creator). **Pas de Page Facebook requise.**
- **App Meta** : « Defi Kilimandjaro Social »
  - App id : `2229681881118640`
  - Cas d'usage : *Gérer les messages et les contenus sur Instagram*
  - Permissions : `instagram_business_basic`, `instagram_business_content_publish`
- **IG user id** : `17841423397309250`
- **Host API** : `graph.instagram.com` · version `v21.0`
- **Mode** : Développement (publie sur le compte propre, sans App Review).

## Le token

Le token est généré depuis l'app Meta → *Personnaliser le cas d'usage* → section
« Générez des tokens d'accès » → **Ajouter un compte** → login `defi_kilimandjaro` → Autoriser.

C'est un **token longue durée (~60 jours)**. Il est stocké :
- en **secret Firebase** pour la Cloud Function : `firebase functions:secrets:set IG_ACCESS_TOKEN` ;
- en local pour les tests dans `tools/instagram/.env` (jamais commité).

### Renouvellement (~tous les 50 jours)
- Soit régénérer un token via « Ajouter un compte » et refaire `functions:secrets:set`.
- Soit (si app id + secret connus) : `python3 tools/instagram/publish.py --refresh-token`.

## Pièges rencontrés (mémo)
- Connexion Facebook bloquée par la **vérification Google** (`redirect_uri_mismatch`) → se connecter
  à Facebook par **mot de passe** (pas « Continuer avec Google »), ou retirer le lien Google ; au pire,
  passer par le **mobile**.
- Login Instagram dans la pop-up Meta : **ne pas mettre le `@`** dans le champ identifiant ; être
  **déjà connecté à instagram.com** dans le même navigateur fait sauter la demande de mot de passe.
- « Rôle de développeur insuffisant » : l'autorisation se fait au moment d'**Ajouter un compte** (la
  connexion vaut acceptation) ; pas besoin de chercher un onglet d'invitation.

## Limites Meta
- 25 publications / 24 h. Pas de DM automatisés. Médias servis depuis une **URL publique** (Firebase Storage).

## Sources
- [Meta — Publish Content (Instagram Platform)](https://developers.facebook.com/docs/instagram-platform/content-publishing/)
- [Meta — Overview of the Instagram API](https://developers.facebook.com/docs/instagram-platform/overview/)
