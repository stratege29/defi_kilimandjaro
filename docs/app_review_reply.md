# Réponse App Review — Kilimandjaro (Guideline 2.1)

> À coller dans **Resolution Center** (réponse au message) ET dans **App Review Information → Notes**.
> Apple écrit en anglais : une réponse en anglais passe mieux. Version EN ci-dessous, version FR en bas.

---

## ✅ Réponse à coller (English)

```
Hello,

Thank you for the review.

LOGIN IS OPTIONAL — NO DEMO ACCOUNT NEEDED
The app does not require any login to access its features. On first launch it
creates an anonymous session automatically, and 100% of the content (solo mode
and the online 1v1 duel) is immediately playable without signing in. "Sign in
with Apple / Google" is an OPTIONAL convenience to sync progress across devices.
There is therefore no demo account to provide — the reviewer can simply open the
app and play.

Below are the requested details.

1. SCREEN RECORDING
   A screen recording captured on a physical iPhone (iOS [VERSION]) is attached,
   showing: app launch → solo word puzzle → victory screen with the cultural
   proverb → mountain progression → online 1v1 duel → in-app purchase flow →
   App Tracking Transparency prompt → optional Apple/Google sign-in → account
   deletion.

2. DEVICES & OS TESTED
   - iPhone 16 Pro (iOS 18.x)
   - iPhone SE 3rd gen (iOS 18.x)
   - iPad (iPadOS 18.x)
   [Adapte à tes vrais appareils]

3. PURPOSE & TARGET AUDIENCE
   Kilimandjaro is a word-connect puzzle game built around West-African
   (Ivorian) culture. Players swipe to link letters and form hidden words; each
   solved word reveals an authentic African proverb narrated by a "griot"
   storyteller. The goal is to climb 51 African summits, from the smallest peak
   to Mount Kilimanjaro. Audience: casual puzzle players and anyone curious about
   African culture. It blends entertainment with cultural learning.

4. SETTING UP / ACCESSING MAIN FEATURES
   No setup or credentials required. Launch the app → tap a mountain → solve word
   puzzles (solo, works offline). For the online duel: tap "Défi" → "Trouver un
   adversaire" (requires internet). Optional: open Profile → sign in with Apple
   or Google to back up progress; the same screen offers account deletion.

5. EXTERNAL SERVICES USED
   - Firebase (Google): anonymous authentication, Firestore, Realtime Database
     (1v1 duels), Cloud Functions (anti-cheat word validation), Analytics,
     Crashlytics, Cloud Messaging.
   - Google AdMob: advertising.
   - Apple In-App Purchase: coin packs and a "No Ads" purchase, validated
     server-side via Cloud Functions.
   - Sign in with Apple / Google Sign-In: optional account linking.

6. REGIONAL DIFFERENCES
   The app functions consistently across all regions. The interface is in French.
   No region-specific content or feature gating.

7. REGULATED INDUSTRY / THIRD-PARTY MATERIAL
   Not applicable. The app is not in a regulated industry. All cultural content
   (proverbs, riddles, illustrations, procedurally generated audio) is original
   and owned by the developer (Ultimes Griots). No protected third-party material
   is used.

PERMISSIONS SHOWN IN THE APP
   - Camera: only to scan a friend's QR code to start a private duel.
   - App Tracking Transparency: shown after the 2nd victory; declining keeps the
     full game available.

Thank you,
Ultimes Griots
```

---

## ⚠️ À vérifier avant de répondre

1. **Suppression de compte in-app** — Apple exige un bouton de suppression de
   compte DANS l'app dès qu'un login existe (même optionnel). Vérifie qu'il y a
   bien « Supprimer mon compte » dans l'écran Profil. Si ce n'est pas le cas,
   c'est un rejet quasi certain au tour suivant : il faut l'ajouter avant de
   resoumettre. (La page support ne suffit pas, Apple veut l'action in-app.)

2. **Permission micro** — ton Info.plist déclare `NSMicrophoneUsageDescription`
   en disant que le micro n'est jamais utilisé. Apple n'aime pas les purpose
   strings de permissions non utilisées. Si le scanner QR n'a pas besoin du micro,
   retire la clé `NSMicrophoneUsageDescription` du build pour éviter un
   Guideline 5.1.1. (Sinon laisse, mais c'est un risque.)

3. **Compte démo malgré tout** — même si le login est optionnel, fournir un vrai
   compte test (Google ou Apple) accélère souvent la revue. Si tu en as un :
   remplis User name / Password dans App Review Information. Sinon, la réponse
   ci-dessus (login optionnel) est valable.

---

## Script de la vidéo (capture sur iPhone physique, iOS à jour)

Ordre à filmer, ~60–90 s, commence par le lancement de l'app :

1. Lancement de l'app (splash → arrive directement dans le jeu, sans login)
2. Hub : choisir une montagne → écran de jeu, relier des lettres, valider un mot
3. Écran de victoire avec le proverbe + griot
4. Liste des sommets (progression)
5. Onglet Défi → « Trouver un adversaire » → un duel 1v1 (au moins le matchmaking + début de duel)
6. Boutique : ouvrir un pack de cauris → lancer le flux d'achat App Store (tu peux annuler avant paiement, mais montre la feuille de paiement Apple)
7. La fenêtre App Tracking Transparency quand elle apparaît
8. Profil → « Se connecter avec Apple » (montre que c'est optionnel) → puis
9. Profil → « Supprimer mon compte » (montre le flux de suppression)

Exporte en .mp4 / .mov et attache-le dans la réponse du Resolution Center.

---

## Version FR (si tu préfères répondre en français)

Le contenu des 7 points ci-dessus, traduit, peut être collé tel quel ; mais
l'anglais est recommandé car les reviewers Apple travaillent en anglais.
