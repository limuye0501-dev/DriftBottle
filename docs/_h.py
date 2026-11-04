import sys
CSS="body{font-family:-apple-system,system-ui,sans-serif;max-width:760px;margin:40px auto;padding:0 20px;line-height:1.6;color:#1b2b3a}h1{color:#0b4f7c}a{color:#0b6fb0}nav a{margin-right:16px}"
def page(title,body):
  return f'<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title} – Drift Bottle</title><style>{CSS}</style></head><body><nav><a href="./">Drift Bottle</a><a href="privacy.html">Privacy</a><a href="terms.html">Terms</a><a href="support.html">Support</a></nav>{body}<hr><p><small>© 2026 Drift Bottle. Last updated 4 November 2026.</small></p></body></html>'
