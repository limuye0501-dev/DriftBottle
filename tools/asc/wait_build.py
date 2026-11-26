#!/usr/bin/env python3
"""Poll App Store Connect until a build's processingState is VALID.

Uses only the Python standard library and openssl. Auth comes from
ASC_KEY_PATH, KEY_ID, and ISSUER_ID (the same secrets as the TestFlight workflow).
Exits 1 on INVALID or FAILED.
"""
import argparse, base64, json, os, subprocess, sys, tempfile, time, urllib.error, urllib.request

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

def der_to_raw(der: bytes) -> bytes:
    """Convert an ECDSA DER signature to the raw 64-byte R||S form JWT expects."""
    def read_len(buf, i):
        n = buf[i]
        if n < 0x80:
            return n, i + 1
        nbytes = n & 0x7F
        return int.from_bytes(buf[i + 1:i + 1 + nbytes], "big"), i + 1 + nbytes
    if der[0] != 0x30:
        raise ValueError("not a DER sequence")
    i = 1
    _, i = read_len(der, i)
    ints = []
    for _ in range(2):
        if der[i] != 0x02:
            raise ValueError("expected integer")
        i += 1
        ln, i = read_len(der, i)
        ints.append(der[i:i + ln])
        i += ln
    def trim(x):
        x = x.lstrip(b"\x00") or b"\x00"
        if len(x) > 32:
            raise ValueError("integer longer than 32 bytes")
        return x.rjust(32, b"\x00")
    return trim(ints[0]) + trim(ints[1])

def token() -> str:
    now = int(time.time())
    header = b64url(json.dumps({"alg": "ES256", "kid": os.environ["KEY_ID"], "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64url(json.dumps({
        "iss": os.environ["ISSUER_ID"], "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1",
    }, separators=(",", ":")).encode())
    signing = f"{header}.{payload}".encode()
    with tempfile.NamedTemporaryFile() as inp, tempfile.NamedTemporaryFile() as out:
        inp.write(signing)
        inp.flush()
        subprocess.check_call(["openssl", "dgst", "-sha256", "-sign", os.environ["ASC_KEY_PATH"], "-out", out.name, inp.name], stdout=subprocess.DEVNULL)
        raw = der_to_raw(open(out.name, "rb").read())
    return signing.decode() + "." + b64url(raw)

def get(url, tok):
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {tok}"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:500]
        raise RuntimeError(f"HTTP {e.code}: {body}") from e

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--app", required=True)
    p.add_argument("--version", required=True, help="CFBundleVersion, e.g. 8")
    p.add_argument("--minutes", type=int, default=40)
    args = p.parse_args()
    deadline = time.time() + args.minutes * 60
    url = (f"https://api.appstoreconnect.apple.com/v1/builds?filter[app]={args.app}"
           f"&filter[version]={args.version}&fields[builds]=processingState,version,uploadedDate&limit=5")
    tok = token()
    minted = time.time()
    while time.time() < deadline:
        if time.time() - minted > 900:
            tok = token()
            minted = time.time()
        try:
            body = get(url, tok)
        except Exception as e:
            print("poll error:", e, flush=True)
            time.sleep(30)
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
    print("timed out waiting for VALID", flush=True)
    return 1

if __name__ == "__main__":
    sys.exit(main())
