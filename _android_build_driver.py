# -*- coding: utf-8 -*-
# Android build driver v2: REAL fork probe + long cooldown retry
import subprocess, time, os, sys

R = r"D:\WorkBuddyFILE\BiLoom"
LOG = os.path.join(R, "_android_build.log")
PROBE = r"D:\dev\_fork_probe.dart"
PYTHON = sys.executable

env = dict(os.environ)
for k in ("HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy", "ALL_PROXY", "all_proxy"):
    env.pop(k, None)

def log(msg):
    with open(LOG, "a", encoding="utf-8", errors="replace") as f:
        f.write(msg + "\n")

def probe_fork():
    """True only if a dart VM can actually spawn a child process."""
    try:
        r = subprocess.run(
            ["dart", PROBE],
            capture_output=True, timeout=90, env=env, cwd=R,
        )
        return r.returncode == 0
    except Exception:
        return False

def build_attempt():
    with open(LOG, "a", encoding="utf-8", errors="replace") as f:
        p = subprocess.run(
            ["dart", "setup.dart", "android", "--arch", "arm64"],
            stdout=f, stderr=subprocess.STDOUT,
            env=env, cwd=R, timeout=7200,
        )
    return p.returncode

HORIZON_MIN = 180        # give up after 3h total
COOLDOWN = 120           # seconds between probes/build retries
start = time.time()

log("=== DRIVER v2 START %s ===" % time.strftime("%F %T"))
attempt = 0
while time.time() - start < HORIZON_MIN * 60:
    if not probe_fork():
        log("fork probe FAIL %s, cooldown %ds" % (time.strftime("%T"), COOLDOWN))
        time.sleep(COOLDOWN)
        continue
    attempt += 1
    log("=== BUILD ATTEMPT %d %s ===" % (attempt, time.strftime("%F %T")))
    try:
        rc = build_attempt()
    except subprocess.TimeoutExpired:
        log("BUILD TIMEOUT 2h")
        rc = 124
    log("BUILD_EXIT=%d" % rc)
    if rc == 0:
        log("=== SUCCESS %s ===" % time.strftime("%F %T"))
        sys.exit(0)
    # non-zero: if pipe-busy signature -> cooldown and loop; else real build error -> stop
    with open(LOG, "rb") as f:
        tail = f.read()[-4000:].decode("utf-8", errors="replace")
    if "process_win.cc" in tail or "231" in tail:
        log("pipe-busy again, cooldown %ds" % COOLDOWN)
        time.sleep(COOLDOWN)
        continue
    log("REAL BUILD ERROR (not pipe-busy), stop.")
    sys.exit(1)

log("=== DRIVER v2 END: horizon reached, dart fork never recovered ===")
sys.exit(2)
