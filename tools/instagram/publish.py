#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Autopilote de publication Instagram — Défi Kilimandjaro.

Utilise l'API Graph (Instagram Platform, content publishing) :
  1) crée un conteneur média (image / carrousel / reel) à partir d'une URL publique
  2) le publie

Aucune dépendance externe (stdlib uniquement).
Les secrets sont lus depuis l'environnement ou tools/instagram/.env — JAMAIS en dur.

Exemples :
  python publish.py --whoami
  python publish.py --exchange-token            # token court -> long (~60 j)
  python publish.py --refresh-token             # prolonge le token long
  python publish.py --image URL --caption "..." [--dry-run]
  python publish.py --carousel URL1 URL2 URL3 --caption "..."
  python publish.py --reel URL --caption "..." [--cover URL]
  python publish.py --queue queue.json --run-due
"""
import argparse, json, os, sys, time, urllib.parse, urllib.request, urllib.error
from datetime import date, datetime

HERE = os.path.dirname(os.path.abspath(__file__))

# ----------------------------------------------------------------------
# Config / .env
# ----------------------------------------------------------------------
def load_env():
    path = os.path.join(HERE, ".env")
    if os.path.exists(path):
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip())

load_env()
GRAPH_HOST    = os.environ.get("GRAPH_HOST", "graph.instagram.com")
GRAPH_VERSION = os.environ.get("GRAPH_VERSION", "v21.0")
IG_USER_ID    = os.environ.get("IG_USER_ID", "")
ACCESS_TOKEN  = os.environ.get("IG_ACCESS_TOKEN", "")
APP_ID        = os.environ.get("IG_APP_ID", "")
APP_SECRET    = os.environ.get("IG_APP_SECRET", "")
IS_IG_LOGIN   = "instagram.com" in GRAPH_HOST

def base_url():
    return f"https://{GRAPH_HOST}/{GRAPH_VERSION}"

# ----------------------------------------------------------------------
# HTTP helpers (urllib)
# ----------------------------------------------------------------------
def _request(method, url, params):
    data = urllib.parse.urlencode(params).encode() if method == "POST" else None
    if method == "GET":
        url = url + ("?" + urllib.parse.urlencode(params) if params else "")
    req = urllib.request.Request(url, data=data, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        body = e.read().decode(errors="replace")
        raise SystemExit(f"[Meta API erreur {e.code}] {body}")

def api_get(path, **params):
    params["access_token"] = ACCESS_TOKEN
    return _request("GET", f"{base_url()}/{path}", params)

def api_post(path, **params):
    params["access_token"] = ACCESS_TOKEN
    return _request("POST", f"{base_url()}/{path}", params)

# ----------------------------------------------------------------------
# Tokens
# ----------------------------------------------------------------------
def exchange_token():
    short = os.environ.get("IG_SHORT_TOKEN", "")
    if not (APP_SECRET and short):
        raise SystemExit("Fournis IG_APP_SECRET et IG_SHORT_TOKEN (et IG_APP_ID pour Facebook login).")
    if IS_IG_LOGIN:
        url = f"https://{GRAPH_HOST}/access_token"
        p = {"grant_type": "ig_exchange_token", "client_secret": APP_SECRET, "access_token": short}
    else:
        url = f"https://graph.facebook.com/{GRAPH_VERSION}/oauth/access_token"
        p = {"grant_type": "fb_exchange_token", "client_id": APP_ID,
             "client_secret": APP_SECRET, "fb_exchange_token": short}
    res = _request("GET", url, p)
    _print_token(res)

def refresh_token():
    if not ACCESS_TOKEN:
        raise SystemExit("IG_ACCESS_TOKEN manquant.")
    if IS_IG_LOGIN:
        url = f"https://{GRAPH_HOST}/refresh_access_token"
        p = {"grant_type": "ig_refresh_token", "access_token": ACCESS_TOKEN}
    else:
        url = f"https://graph.facebook.com/{GRAPH_VERSION}/oauth/access_token"
        p = {"grant_type": "fb_exchange_token", "client_id": APP_ID,
             "client_secret": APP_SECRET, "fb_exchange_token": ACCESS_TOKEN}
    res = _request("GET", url, p)
    _print_token(res)

def _print_token(res):
    tok = res.get("access_token", "")
    exp = res.get("expires_in")
    print("Token longue durée :")
    print(tok)
    if exp:
        print(f"Expire dans ~{int(exp)//86400} jours.")
    print("\n→ Copie-le dans tools/instagram/.env (IG_ACCESS_TOKEN=...).")

def whoami():
    me = api_get("me", fields="user_id,username" if IS_IG_LOGIN else "id,username")
    print(json.dumps(me, indent=2, ensure_ascii=False))

# ----------------------------------------------------------------------
# Publication
# ----------------------------------------------------------------------
def _require_account():
    if not (IG_USER_ID and ACCESS_TOKEN):
        raise SystemExit("IG_USER_ID et IG_ACCESS_TOKEN requis (voir .env / guide setup).")

def _wait_ready(container_id, label="média", tries=30, delay=5):
    for _ in range(tries):
        st = api_get(container_id, fields="status_code")
        code = st.get("status_code")
        if code == "FINISHED":
            return
        if code == "ERROR":
            raise SystemExit(f"Conteneur {label} en ERROR : {st}")
        time.sleep(delay)
    raise SystemExit(f"Conteneur {label} pas prêt après {tries*delay}s.")

def publish_image(image_url, caption, dry=False):
    _require_account()
    if dry:
        print(f"[dry-run] IMAGE -> {image_url}\n  légende: {caption[:60]}…")
        return None
    c = api_post(f"{IG_USER_ID}/media", image_url=image_url, caption=caption)
    cid = c["id"]
    res = api_post(f"{IG_USER_ID}/media_publish", creation_id=cid)
    print(f"✅ Image publiée : {res}")
    return res

def publish_carousel(image_urls, caption, dry=False):
    _require_account()
    if dry:
        print(f"[dry-run] CARROUSEL ({len(image_urls)} slides)\n  légende: {caption[:60]}…")
        for u in image_urls: print("   -", u)
        return None
    child_ids = []
    for u in image_urls:
        c = api_post(f"{IG_USER_ID}/media", image_url=u, is_carousel_item="true")
        child_ids.append(c["id"])
    cont = api_post(f"{IG_USER_ID}/media", media_type="CAROUSEL",
                    children=",".join(child_ids), caption=caption)
    res = api_post(f"{IG_USER_ID}/media_publish", creation_id=cont["id"])
    print(f"✅ Carrousel publié : {res}")
    return res

def publish_reel(video_url, caption, cover_url=None, dry=False):
    _require_account()
    if dry:
        print(f"[dry-run] REEL -> {video_url}\n  légende: {caption[:60]}…")
        return None
    params = dict(media_type="REELS", video_url=video_url, caption=caption)
    if cover_url:
        params["cover_url"] = cover_url
    c = api_post(f"{IG_USER_ID}/media", **params)
    _wait_ready(c["id"], "reel")
    res = api_post(f"{IG_USER_ID}/media_publish", creation_id=c["id"])
    print(f"✅ Reel publié : {res}")
    return res

# ----------------------------------------------------------------------
# File d'attente (queue.json)
# ----------------------------------------------------------------------
def publish_item(item, dry=False):
    t = item.get("type")
    cap = item.get("caption", "")
    if t == "image":
        return publish_image(item["url"], cap, dry)
    if t == "carousel":
        return publish_carousel(item["urls"], cap, dry)
    if t == "reel":
        return publish_reel(item["url"], cap, item.get("cover"), dry)
    raise SystemExit(f"Type inconnu : {t}")

def run_queue(path, run_due=False, dry=False):
    with open(path, encoding="utf-8") as f:
        queue = json.load(f)
    today = date.today().isoformat()
    changed = False
    for item in queue:
        if item.get("posted"):
            continue
        due = item.get("date", "9999-01-01")
        if run_due and due > today:
            continue
        print(f"\n── {item.get('date')} · {item.get('type')} · {item.get('label','')} ──")
        publish_item(item, dry)
        if not dry:
            item["posted"] = True
            item["posted_at"] = datetime.now().isoformat(timespec="seconds")
            changed = True
        if run_due:
            break
    if changed:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(queue, f, indent=2, ensure_ascii=False)
        print("\nFile mise à jour.")

# ----------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser(description="Autopilote Instagram — Défi Kilimandjaro")
    ap.add_argument("--whoami", action="store_true")
    ap.add_argument("--exchange-token", action="store_true")
    ap.add_argument("--refresh-token", action="store_true")
    ap.add_argument("--image")
    ap.add_argument("--carousel", nargs="+")
    ap.add_argument("--reel")
    ap.add_argument("--cover")
    ap.add_argument("--caption", default="")
    ap.add_argument("--queue")
    ap.add_argument("--run-due", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()

    if a.whoami:            return whoami()
    if a.exchange_token:    return exchange_token()
    if a.refresh_token:     return refresh_token()
    if a.image:             return publish_image(a.image, a.caption, a.dry_run)
    if a.carousel:          return publish_carousel(a.carousel, a.caption, a.dry_run)
    if a.reel:              return publish_reel(a.reel, a.caption, a.cover, a.dry_run)
    if a.queue:             return run_queue(a.queue, a.run_due, a.dry_run)
    ap.print_help()

if __name__ == "__main__":
    main()
