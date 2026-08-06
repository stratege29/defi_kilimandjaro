# Site légal Kilimandjaro (kilimandjaro-legal.web.app)

Dossier de déploiement **autonome** reconstruit depuis le site live (la source d'origine
était introuvable sur la machine). Sert la landing + politique de confidentialité + support,
**plus** le fichier `app-ads.txt` requis par AdMob.

## Contenu
- `public/index.html` — landing (liens privacy + support)
- `public/privacy.html` — politique de confidentialité (contenu inchangé vs live, daté du 7 juin 2026)
- `public/support.html` — page support + FAQ
- `public/app-ads.txt` — autorisation vendeur AdMob : `google.com, pub-3872682728320036, DIRECT, f08c47fec0942fa0`

## Déployer
```bash
cd legal_site
firebase login --reauth          # les creds CLI étaient expirés
firebase deploy --only hosting   # site ciblé : kilimandjaro-legal
```
Si le projet n'est pas `kilimandjaro-dev`, ajuste `.firebaserc` (ou `--project <id>`).
Vérifier ensuite : https://kilimandjaro-legal.web.app/app-ads.txt (doit afficher la ligne)
et que https://kilimandjaro-legal.web.app/privacy s'affiche toujours correctement.

## Après déploiement
Dans AdMob → chaque app → App settings → App verification → **Check for updates**
pour lever « Not verified ».
