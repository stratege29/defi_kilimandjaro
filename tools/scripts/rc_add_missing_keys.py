#!/usr/bin/env python3
"""Ajoute au Remote Config d'un projet les clés manquantes du template local.

Additif et sûr : le template EN LIGNE reste la référence (conditions, valeurs
conditionnelles, groupes) ; seules les clés présentes dans
`remoteconfig.template.json` et absentes en ligne sont ajoutées, avec leur
valeur par défaut. Rien n'est jamais écrasé ni supprimé.

Auth : identifiants applicatifs Google en process (`google.auth.default`),
jamais de token imprimé. Prérequis :

    gcloud auth application-default login   # compte kossea@ultimesgriots.com

Usage :

    python3 tools/scripts/rc_add_missing_keys.py --project kilimandjaro-dev
    python3 tools/scripts/rc_add_missing_keys.py --project kilimandjaro-dev --apply
    python3 tools/scripts/rc_add_missing_keys.py --project kilimandjaro-prod --apply

Sans `--apply`, le script affiche le diff et s'arrête (dry-run). Avec
`--apply`, il valide le template auprès de l'API (`?validate_only=true`)
puis publie avec l'ETag lu, ce qui échoue proprement si quelqu'un a modifié
le template entre-temps.
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys
import urllib.error
import urllib.request

API = "https://firebaseremoteconfig.googleapis.com/v1/projects/{project}/remoteConfig"
SCOPES = ["https://www.googleapis.com/auth/cloud-platform"]
ROOT = pathlib.Path(__file__).resolve().parents[2]
LOCAL_TEMPLATE = ROOT / "remoteconfig.template.json"


def _credentials():
    try:
        import google.auth
        import google.auth.transport.requests
    except ImportError:
        sys.exit("google-auth manquant : pip3 install google-auth")
    creds, _ = google.auth.default(scopes=SCOPES)
    creds.refresh(google.auth.transport.requests.Request())
    return creds


def _request(creds, url: str, method: str = "GET", body: dict | None = None,
             etag: str | None = None, quota_project: str | None = None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {
        "Authorization": f"Bearer {creds.token}",
        "Content-Type": "application/json; UTF-8",
    }
    # Identifiants utilisateur (ADC) : l'API exige un projet de quota explicite.
    if quota_project:
        headers["x-goog-user-project"] = quota_project
    if etag:
        headers["If-Match"] = etag
    req = urllib.request.Request(url, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req) as resp:
            return resp.headers.get("ETag"), json.load(resp)
    except urllib.error.HTTPError as err:
        detail = err.read().decode(errors="replace")[:600]
        sys.exit(f"HTTP {err.code} sur {method} {url}\n{detail}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--project", required=True, help="kilimandjaro-dev ou kilimandjaro-prod")
    parser.add_argument("--apply", action="store_true", help="publie (sinon dry-run)")
    parser.add_argument("--keys", nargs="*", help="restreindre aux clés listées")
    args = parser.parse_args()

    local = json.loads(LOCAL_TEMPLATE.read_text(encoding="utf-8"))
    local_params: dict = local.get("parameters", {})
    wanted = set(args.keys) if args.keys else set(local_params)

    creds = _credentials()
    url = API.format(project=args.project)
    etag, remote = _request(creds, url, quota_project=args.project)
    remote_params: dict = remote.setdefault("parameters", {})

    missing = sorted(k for k in wanted if k in local_params and k not in remote_params)
    unknown = sorted(k for k in wanted if k not in local_params)
    if unknown:
        print(f"Ignorées (absentes du template local) : {', '.join(unknown)}")
    if not missing:
        print(f"{args.project} : rien à ajouter, les {len(wanted)} clés existent déjà.")
        return

    print(f"{args.project} : {len(missing)} clé(s) à ajouter")
    for key in missing:
        param = local_params[key]
        default = param.get("defaultValue", {}).get("value")
        print(f"  + {key} = {default!r}  ({param.get('valueType', '?')})")
        remote_params[key] = param

    if not args.apply:
        print("Dry-run : relancer avec --apply pour valider puis publier.")
        return

    _request(creds, url + "?validate_only=true", "PUT", remote, etag, args.project)
    new_etag, _ = _request(creds, url, "PUT", remote, etag, args.project)
    print(f"Publié sur {args.project} (nouvelle version, ETag reçu : {'oui' if new_etag else 'non'}).")


if __name__ == "__main__":
    main()
