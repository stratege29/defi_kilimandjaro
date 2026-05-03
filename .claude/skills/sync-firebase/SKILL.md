---
name: sync-firebase
description: Deploy Firebase backend (Cloud Functions, Firestore rules, Realtime DB rules, indexes) to the dev or prod project after validation. Runs lint and emulator tests first.
disable-model-invocation: true
---

# Sync Firebase

Deploy Firebase configuration to: $ARGUMENTS (default: `dev`)

## Steps

1. **Determine target project**:
   - `dev` → `kilimandjaro-dev`
   - `prod` → `kilimandjaro-prod` (REQUIRES explicit user confirmation)
   - Default: `dev` if no argument

2. **Pre-flight checks** (abort if any fail):
   - `git status` is clean (no uncommitted changes)
   - Current branch is `main` for prod, any branch for dev
   - `firebase use <project>` succeeds
   - `cd functions && npm run lint` passes
   - `cd functions && npm run build` (TypeScript compile) passes

3. **Run emulator tests**:
   ```bash
   firebase emulators:exec --project=demo-test "cd functions && npm test"
   ```
   Abort on failure.

4. **For PROD only**:
   - Explicitly ask user "Confirm deploy to PROD `kilimandjaro-prod`? Type YES."
   - If not YES, abort.

5. **Deploy in order**:
   ```bash
   firebase deploy --only firestore:rules --project <project>
   firebase deploy --only firestore:indexes --project <project>
   firebase deploy --only database --project <project>
   firebase deploy --only functions --project <project>
   firebase deploy --only remoteconfig --project <project>
   ```

6. **Post-deploy verification**:
   ```bash
   firebase functions:log --project <project> --limit 20
   ```
   Look for any startup errors.

7. **Report**:
   - Functions deployed (list with versions)
   - Rules version
   - Any warning or error

## Constraints

- NEVER deploy to prod without explicit YES confirmation
- NEVER `firebase deploy` without prior emulator test
- NEVER bypass the lint check
- If `firebase login` is missing, instruct the user to run it manually (don't try `--token` for prod)
