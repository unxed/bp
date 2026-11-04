#!/usr/bin/env python3
"""Waits for the CI of a pull request and fails fast.

ci-wait.py PR [--merge]

Reads the jobs of the latest run for the head commit of PR (not the check summary of the PR, which GitHub sometimes
leaves "in progress" after every job has finished) and prints a line whenever their state changes.
- Every job succeeded: exit 0; with --merge the PR is merged (gh pr merge --merge --delete-branch) first.
- A job failed in its own steps (a build or a test): exit 1 at once, with the end of the failed log.
- A job failed on the runner (cancelled, timed out, or failed in an install step), or waits for a runner longer than
  QUEUE minutes: the run is started again, once; a second such failure is exit 1.
- No result after LIMIT minutes in all: exit 2.
QUEUE (default 4) and LIMIT (default 30) are environment variables. Needs gh, logged in.
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

QUEUE = float(os.environ.get("QUEUE", "4")) * 60
LIMIT = float(os.environ.get("LIMIT", "30")) * 60
POLL = 15


def gh(*args, check=True):
    r = subprocess.run(["gh", *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        raise RuntimeError("gh %s: %s" % (" ".join(args), r.stderr.strip()))
    return r.stdout


def api(path):
    return json.loads(gh("api", path))


def age(stamp):
    if not stamp:
        return 0
    t = datetime.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
    return (datetime.now(timezone.utc) - t).total_seconds()


def say(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def infra_failure(job):
    """A failure of the runner rather than of the code: the job did not run its own steps to a verdict."""
    if job["conclusion"] in ("cancelled", "timed_out", "startup_failure"):
        return True
    failed = [s["name"] for s in job.get("steps", []) if s.get("conclusion") == "failure"]
    return any(n.startswith(("Install", "Set up job")) for n in failed)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    pr, merge = sys.argv[1], "--merge" in sys.argv[2:]
    repo = gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").strip()
    sha = gh("pr", "view", pr, "--json", "headRefOid", "-q", ".headRefOid").strip()
    start, reruns, last = time.time(), 0, None
    while True:
        if time.time() - start > LIMIT:
            say("ci-wait: no result in %d min" % (LIMIT // 60))
            sys.exit(2)
        runs = api("repos/%s/actions/runs?head_sha=%s&per_page=20" % (repo, sha))["workflow_runs"]
        if not runs:
            time.sleep(POLL)
            continue
        run = max(runs, key=lambda r: (r["created_at"], r["run_attempt"]))
        jobs = api("repos/%s/actions/runs/%d/attempts/%d/jobs?per_page=100"
                   % (repo, run["id"], run["run_attempt"]))["jobs"]
        state = " ".join("%s:%s" % (j["name"], j["conclusion"] or j["status"])
                         for j in sorted(jobs, key=lambda j: j["name"]))
        if state != last:
            say("run %d attempt %d: %s" % (run["id"], run["run_attempt"], state or "(no jobs yet)"))
            last = state
        stuck = [j for j in jobs if j["status"] in ("queued", "waiting", "pending") and age(j["created_at"]) > QUEUE]
        done = jobs and all(j["status"] == "completed" for j in jobs)
        bad = [j for j in jobs if j["status"] == "completed" and j["conclusion"] not in ("success", "skipped")]
        real = [j for j in bad if not infra_failure(j)]
        if real:
            say("ci-wait: FAILED: %s" % ", ".join(j["name"] for j in real))
            print(gh("run", "view", str(run["id"]), "--log-failed", check=False)[-4000:])
            sys.exit(1)
        if stuck or (done and bad):
            why = "waits for a runner" if stuck else "failed on the runner"
            names = ", ".join(j["name"] for j in (stuck or bad))
            if reruns >= 1:
                say("ci-wait: FAILED again (%s %s)" % (names, why))
                sys.exit(1)
            say("ci-wait: %s %s: starting the run again" % (names, why))
            if not done:
                gh("run", "cancel", str(run["id"]), check=False)
                while api("repos/%s/actions/runs/%d" % (repo, run["id"]))["status"] != "completed":
                    time.sleep(5)
            gh("run", "rerun", str(run["id"]), *([] if stuck else ["--failed"]))
            reruns += 1
            last = None
            time.sleep(POLL)
            continue
        if done:
            if run["status"] != "completed":
                say("ci-wait: every job passed (GitHub still shows the run as %s)" % run["status"])
            else:
                say("ci-wait: every job passed")
            if merge:
                print(gh("pr", "merge", pr, "--merge", "--delete-branch", check=False).strip())
                say("ci-wait: PR %s %s" % (pr, gh("pr", "view", pr, "--json", "state", "-q", ".state").strip()))
            sys.exit(0)
        time.sleep(POLL)


if __name__ == "__main__":
    main()
