#!/usr/bin/env python3
"""Waits for the CI of a pull request and fails fast.

ci-wait.py PR [--merge]

Reads the jobs of the latest run for the head commit of PR (not the check summary of the PR, which GitHub sometimes
leaves "in progress" after every job has finished) and prints a line whenever their state changes.
- Every job succeeded: exit 0; with --merge the PR is merged (gh pr merge --merge --delete-branch) first.
- A job failed in its own steps (a build or a test): exit 1 at once, with the end of the failed log.
- A job failed on the runner (cancelled, timed out, or failed in an install step), waits for a runner longer than
  QUEUE minutes, or hangs in a step: the run is cancelled at once and its failed jobs started again, up to RERUNS
  times; one more such failure is exit 1. A step hangs when it runs longer than 3 times the same step of the last
  successful run of the workflow plus 2 minutes; an install step (a name that starts with "Install", where a slow apt
  mirror stalls: 15 s as a rule, 13 and 20 minutes when it stalled) after STALL minutes at most.
- No result after LIMIT minutes in all: exit 2.
- A call of gh that fails on the network (a timeout, no connection, a 5xx of the gateway) is made again after a pause,
  up to 8 times, so a short outage does not end the wait.
- A PR that changes only texts (*.md, *.txt): only the jobs that check texts (a name with "text") are waited for; with
  none, it is merged at once.
QUEUE (default 4), STALL (default 4), RERUNS (default 2) and LIMIT (default 30) are environment variables. Needs gh,
logged in.
"""
import json
import os
import subprocess
import sys
import time
from datetime import datetime, timezone

QUEUE = float(os.environ.get("QUEUE", "4")) * 60
STALL = float(os.environ.get("STALL", "4")) * 60
RERUNS = int(os.environ.get("RERUNS", "2"))
LIMIT = float(os.environ.get("LIMIT", "30")) * 60
POLL = 15


# the errors of the network, not of the request: the call is made again after a pause, up to NET_TRIES times
NET_ERRORS = ("error connecting to api.github.com", "TLS handshake timeout", "i/o timeout", "connection reset",
              "no such host", "HTTP 502", "HTTP 503", "HTTP 504")
NET_TRIES = 8


def gh(*args, check=True):
    for n in range(NET_TRIES):
        r = subprocess.run(["gh", *args], capture_output=True, text=True)
        if r.returncode == 0 or not any(e in r.stderr for e in NET_ERRORS) or n == NET_TRIES - 1:
            break
        print("%s ci-wait: the network failed (%s): again in %d s"
              % (time.strftime("%H:%M:%S"), r.stderr.strip().splitlines()[-1][:80], POLL), flush=True)
        time.sleep(POLL)
    if check and r.returncode != 0:
        raise RuntimeError("gh %s: %s" % (" ".join(args), r.stderr.strip()))
    return r.stdout


def api(path):
    return json.loads(gh("api", path))


def when(stamp):
    return datetime.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)


def age(stamp):
    if not stamp:
        return 0
    return (datetime.now(timezone.utc) - when(stamp)).total_seconds()


def baseline(repo, run):
    """The seconds of each (job, step) that succeeded in the last successful run of the workflow of RUN."""
    runs = api("repos/%s/actions/workflows/%d/runs?status=success&per_page=1" % (repo, run["workflow_id"]))
    result = {}
    for r in runs["workflow_runs"][:1]:
        jobs = api("repos/%s/actions/runs/%d/attempts/%d/jobs?per_page=100" % (repo, r["id"], r["run_attempt"]))
        for j in jobs["jobs"]:
            for s in j.get("steps", []):
                if s.get("conclusion") == "success" and s.get("started_at") and s.get("completed_at"):
                    result[j["name"], s["name"]] = (when(s["completed_at"]) - when(s["started_at"])).total_seconds()
    return result


def hung(job, base):
    """The step of a running job that runs far longer than it should, as "step (N s)", or None."""
    for s in job.get("steps", []):
        if s.get("status") != "in_progress" or not s.get("started_at"):
            continue
        b = base.get((job["name"], s["name"]))
        limit = 3 * b + 120 if b is not None else None
        if s["name"].startswith("Install"):
            limit = STALL if limit is None else min(limit, STALL)
        if limit is not None and age(s["started_at"]) > limit:
            return "%s (%d s, the limit %d s)" % (s["name"], age(s["started_at"]), limit)
    return None


def say(msg):
    print(time.strftime("%H:%M:%S"), msg, flush=True)


def infra_failure(job):
    """A failure of the runner rather than of the code: the job did not run its own steps to a verdict."""
    if job["conclusion"] in ("cancelled", "timed_out", "startup_failure"):
        return True
    failed = [s["name"] for s in job.get("steps", []) if s.get("conclusion") == "failure"]
    return any(n.startswith(("Install", "Set up job")) for n in failed)


TEXT = (".md", ".txt")


def text_only(pr):
    """The PR changes only texts (Markdown, plain text): only the jobs that check texts matter."""
    files = gh("pr", "view", pr, "--json", "files", "-q", ".files[].path").split()
    return bool(files) and all(f.lower().endswith(TEXT) for f in files)


def text_job(job):
    return "text" in job["name"].lower()


def merge_now(pr, merge):
    if merge:
        print(gh("pr", "merge", pr, "--merge", "--delete-branch", check=False).strip())
        say("ci-wait: PR %s %s" % (pr, gh("pr", "view", pr, "--json", "state", "-q", ".state").strip()))
    sys.exit(0)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    pr, merge = sys.argv[1], "--merge" in sys.argv[2:]
    repo = gh("repo", "view", "--json", "nameWithOwner", "-q", ".nameWithOwner").strip()
    sha = gh("pr", "view", pr, "--json", "headRefOid", "-q", ".headRefOid").strip()
    start, reruns, last, base = time.time(), 0, None, None
    texts = text_only(pr)
    if texts:
        say("ci-wait: the PR changes only texts: waiting only for the jobs that check texts")
    while True:
        if time.time() - start > LIMIT:
            say("ci-wait: no result in %d min" % (LIMIT // 60))
            sys.exit(2)
        runs = api("repos/%s/actions/runs?head_sha=%s&per_page=20" % (repo, sha))["workflow_runs"]
        if not runs and texts and time.time() - start > 60:
            say("ci-wait: no CI run checks texts: nothing to wait for")
            merge_now(pr, merge)
        if not runs:
            time.sleep(POLL)
            continue
        run = max(runs, key=lambda r: (r["created_at"], r["run_attempt"]))
        jobs = api("repos/%s/actions/runs/%d/attempts/%d/jobs?per_page=100"
                   % (repo, run["id"], run["run_attempt"]))["jobs"]
        if texts:
            jobs = [j for j in jobs if text_job(j)]
            if not jobs and run["status"] == "completed" or not jobs and age(run["created_at"]) > 60:
                say("ci-wait: no job checks texts: nothing to wait for")
                merge_now(pr, merge)
        state = " ".join("%s:%s" % (j["name"], j["conclusion"] or j["status"])
                         for j in sorted(jobs, key=lambda j: j["name"]))
        if state != last:
            say("run %d attempt %d: %s" % (run["id"], run["run_attempt"], state or "(no jobs yet)"))
            last = state
        if base is None:
            try:
                base = baseline(repo, run)
            except (RuntimeError, KeyError, ValueError):
                base = {}
        stuck = [j for j in jobs if j["status"] in ("queued", "waiting", "pending") and age(j["created_at"]) > QUEUE]
        hangs = {j["name"]: hung(j, base) for j in jobs if j["status"] == "in_progress"}
        hangs = {k: v for k, v in hangs.items() if v}
        done = jobs and all(j["status"] == "completed" for j in jobs)
        bad = [j for j in jobs if j["status"] == "completed" and j["conclusion"] not in ("success", "skipped")]
        real = [j for j in bad if not infra_failure(j)]
        if real:
            say("ci-wait: FAILED: %s" % ", ".join(j["name"] for j in real))
            print(gh("run", "view", str(run["id"]), "--log-failed", check=False)[-4000:])
            sys.exit(1)
        if stuck or hangs or (done and bad):
            if stuck:
                why, names = "waits for a runner", ", ".join(j["name"] for j in stuck)
            elif hangs:
                why, names = "hangs", ", ".join("%s in %s" % kv for kv in hangs.items())
            else:
                why, names = "failed on the runner", ", ".join(j["name"] for j in bad)
            if reruns >= RERUNS:
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
            merge_now(pr, merge)
        time.sleep(POLL)


if __name__ == "__main__":
    main()
