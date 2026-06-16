# tools/instagram — Test & publication manuelle Instagram

Script de publication/test via l'API Graph. **L'autopilote de production tourne en
Cloud Function** (voir `docs/instagram_cloud_function.md`) — ce script sert au test
local du token et aux publications manuelles ponctuelles.

## Prérequis
- Python 3 (stdlib uniquement, aucune dépendance).
- Compte Instagram **Professionnel** + app Meta (voir `docs/instagram_setup_meta.md`).
- Token dans `.env` (copié depuis `.env.example`).

## Commandes
```bash
cd tools/instagram

# Tester le token (le plus utile)
IG_ACCESS_TOKEN=COLLE_TON_TOKEN python3 publish.py --whoami

# Publier (test à blanc d'abord)
python3 publish.py --image "https://.../post.png" --caption "Légende" --dry-run
python3 publish.py --image "https://.../post.png" --caption "Légende"

# Carrousel
python3 publish.py --carousel URL1 URL2 URL3 --caption "Légende"

# Reel (vidéo 9:16 hébergée publiquement)
python3 publish.py --reel "https://.../reel.mp4" --cover "https://.../cover.png" --caption "Légende"

# Échanger / prolonger le token
IG_APP_SECRET=xxx IG_SHORT_TOKEN=yyy python3 publish.py --exchange-token
python3 publish.py --refresh-token
```

## Sécurité
Les secrets vivent dans `.env` (ignoré par git). Jamais de token/clé en dur.

## Note
Pour publier, l'API exige une **URL publique** par média (héberger sur Firebase Storage).
La publication récurrente est gérée côté serveur par la Cloud Function `publishScheduledInstagramPost`.
