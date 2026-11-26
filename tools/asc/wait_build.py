#!/usr/bin/env python3
"""Poll App Store Connect until a build's processingState is VALID. Exits 1 on INVALID or FAILED."""
import argparse, json, os, sys, time, urllib.request
import jwt

def token():
    key = open(os.environ["ASC_KEY_PATH"]).read()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"},
        key, algorithm="ES256", headers={"kid": os.environ["KEY_ID"], "typ": "JWT"},
    )

def get(url, tok):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--app", required=True)
    p.add_argument("--version", required=True, help="CFBundleVersion, e.g. 8")
    p.add_argument("--minutes", type=int, default=40)
    args = p.parse_args()
    deadline = time.time() + args.minutes * 60
    url = f"https://api.appstoreconnect.apple.com/v1/builds?filter[app]={args.app}&filter[version]={args.version}&fields[builds]=processingState,version,uploadedDate&limit=5"
    tok = token()
    while time.time() < deadline:
        try:
            body = get(url, tok)
        except Exception as e:
            print("poll error:", e, flush=True)
            time.sleep(30)
            tok = token()
            continue
        builds = body.get("data") or []
        if not builds:
            print(f"build {args.version} not listed yet", flush=True)
        else:
            state = builds[0].get("attributes", {}).get("processingState")
            print(f"build {args.version} processingState={state}", flush=True)
            if state == "VALID":
                return 0
            if state in ("INVALID", "FAILED"):
                return 1
        time.sleep(30)
        if time.time() > deadline - 120:
            tok = token()
    print("timed out waiting for VALID", flush=True)
    return 1

if __name__ == "__main__":
    sys.exit(main())
