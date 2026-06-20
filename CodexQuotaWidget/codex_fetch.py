#!/usr/bin/env python3
"""Codex Quota Fetcher — portable external script.

Reads proxy config from env vars passed by the host app:
  CODEX_PROXY_HOST / CODEX_PROXY_PORT  — manual override (preferred)
  or inherits HTTP_PROXY / HTTPS_PROXY  — system proxy auto-detected
  or no proxy                           — direct connect (e.g. outside China)

Codex binary is resolved from PATH (with auto-repair for GUI-launched envs).
"""
import subprocess, json, time, select, sys, os

result_file = sys.argv[1]

# ── Proxy setup ──────────────────────────────────────────────
def _set_proxy():
    """Apply proxy from CODEX_PROXY_* env vars if provided."""
    host = os.environ.get("CODEX_PROXY_HOST", "").strip()
    port = os.environ.get("CODEX_PROXY_PORT", "").strip()
    if host and port:
        url = f"http://{host}:{port}"
        os.environ["HTTP_PROXY"]  = url
        os.environ["HTTPS_PROXY"] = url
        os.environ["http_proxy"]  = url
        os.environ["https_proxy"] = url
        return url
    # No explicit proxy — inherit whatever the parent set
    return os.environ.get("http_proxy") or os.environ.get("HTTP_PROXY") or "(none)"

proxy_url = _set_proxy()
# Always remove these to avoid precedence issues with Rust's reqwest
os.environ.pop("ALL_PROXY", None)
os.environ.pop("all_proxy", None)

# ── PATH repair (GUI apps don't inherit shell PATH) ──────────
for d in ["/opt/homebrew/bin", "/opt/homebrew/sbin", "/usr/local/bin"]:
    if d not in os.environ.get("PATH", "").split(":") and os.path.isdir(d):
        os.environ["PATH"] = d + ":" + os.environ.get("PATH", "")

# Resolve codex binary
codex_bin = None
for candidate in ["codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex"]:
    if subprocess.run(["which", candidate], capture_output=True).returncode == 0:
        codex_bin = candidate
        break
if not codex_bin:
    codex_bin = "codex"  # last resort — let the shell fail with a clear error

# ── Logging ──────────────────────────────────────────────────
def w(msg):
    print(f"[Python] {msg}", file=sys.stderr, flush=True)

w(f"proxy={proxy_url}  codex={codex_bin}")
w(f"HOME={os.environ.get('HOME','(missing)')}")

# ── Launch Codex CLI ─────────────────────────────────────────
proc = subprocess.Popen(
    [codex_bin, "app-server", "--listen", "stdio://"],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    env=os.environ,
)
w(f"PID={proc.pid}")

# Check if Codex crashed immediately (e.g. missing node)
time.sleep(1.0)
if proc.poll() is not None:
    _, err_data = proc.communicate()
    err_text = err_data.decode("utf-8", errors="replace").strip()
    w(f"CRASH  code={proc.returncode}  stderr={err_text[:400]}")
    with open(result_file, "w") as f:
        json.dump({"ok": False, "error": f"Codex CLI exited early (code={proc.returncode}): {err_text[:300]}"}, f)
    sys.exit(1)

# ── Safe stdin write ─────────────────────────────────────────
def wr(data):
    try:
        proc.stdin.write((data + "\n").encode())
        proc.stdin.flush()
        return True
    except (BrokenPipeError, OSError) as e:
        _, err_data = proc.communicate()
        err_text = err_data.decode("utf-8", errors="replace").strip()
        w(f"WRITE-FAIL  {e}  stderr={err_text[:300]}")
        return False

# ── JSON-RPC conversation ────────────────────────────────────
try:
    init_msg = json.dumps({
        "id": 1, "method": "initialize",
        "params": {"clientInfo": {"name": "codex-quota-widget", "version": "1.0.0"}}
    })
    if not wr(init_msg):
        with open(result_file, "w") as f:
            json.dump({"ok": False, "error": "Codex CLI died during init"}, f)
        sys.exit(1)

    time.sleep(1.2)

    rl_msg = json.dumps({"id": 2, "method": "account/rateLimits/read"})
    if not wr(rl_msg):
        with open(result_file, "w") as f:
            json.dump({"ok": False, "error": "Broken pipe on rateLimits request"}, f)
        sys.exit(1)

    w("sent-rateLimits")

    # Read response with 16 s timeout
    start = time.time()
    while time.time() - start < 16:
        r, _, _ = select.select([proc.stdout, proc.stderr], [], [], 1)
        for stream in r:
            line = stream.readline()
            if not line:
                break
            decoded = line.decode("utf-8", errors="replace").strip()
            if stream is proc.stdout:
                try:
                    obj = json.loads(decoded)
                    if obj.get("id") == 2:
                        if "result" in obj:
                            rl = obj["result"]["rateLimits"]
                            p = rl["primary"]["usedPercent"]
                            s = rl["secondary"]["usedPercent"]
                            # resetsAt lives at primary level or top level
                            resets = (
                                rl["primary"].get("resetsAt") or
                                rl.get("resetsAt")
                            )
                            with open(result_file, "w") as f:
                                out = {
                                    "ok": True,
                                    "remainingPercent": 100 - int(round(p)),
                                    "usedPercent": int(round(p)),
                                    "planType": rl.get("planType", "unknown"),
                                    "primaryRemaining": 100 - int(round(p)),
                                    "secondaryRemaining": 100 - int(round(s)),
                                }
                                if resets:
                                    out["resetsAt"] = resets
                                json.dump(out, f)
                            w("OK")
                            sys.exit(0)
                        elif "error" in obj:
                            em = obj["error"].get("message", "?")
                            with open(result_file, "w") as f:
                                json.dump({"ok": False, "error": em}, f)
                            w(f"codex-error: {em}")
                            sys.exit(1)
                except Exception:
                    pass
            else:
                w(f"[ERR] {decoded[:200]}")

    with open(result_file, "w") as f:
        json.dump({"ok": False, "error": "timeout"}, f)
    sys.exit(1)

except Exception as e:
    import traceback
    w(f"FATAL: {e}")
    traceback.print_exc(file=sys.stderr)
    with open(result_file, "w") as f:
        json.dump({"ok": False, "error": str(e)}, f)
    sys.exit(1)
finally:
    for h in [proc.stdin, proc.stdout, proc.stderr]:
        if h:
            try: h.close()
            except: pass
