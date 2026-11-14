#!/usr/bin/env python3
"""Classify GitHub Actions check runs for the production deploy catch-up.

The catch-up refuses to deploy origin/main while CI is still running or has
failed. This helper is the cheap check: one public API read of the commit's
check runs (the repo is public), deduped to the latest run of each job name.

Stdout is exactly two lines:
  green|pending|red|empty|unknown
  <human reason>

Exit 0 when a verdict was printed, including "unknown" for network and HTTP
errors. Exit 2 for a usage or local parse error with an empty or partial
verdict the caller should treat as unknown.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import urllib.error
import urllib.request
from typing import Any, Dict, List, Optional, Tuple

DEFAULT_REPO = "brianlane/bizblasts"
OK_CONCLUSIONS = {"success", "neutral", "skipped"}
BAD_CONCLUSIONS = {
    "failure",
    "cancelled",
    "timed_out",
    "action_required",
    "stale",
    "startup_failure",
}
# Bookkeeping workflows, not the code CI that gates a production deploy.
# auto-merge is skipped on pushes to main; a failure there must not pin prod.
DEFAULT_IGNORE = "auto-merge,label-dependabot,deploy"
MAX_PAGES = 5
SHA_RE = re.compile(r"^[0-9a-fA-F]{7,40}$")


def ignored_names() -> set:
    raw = os.environ.get("BIZBLASTS_CI_IGNORE", DEFAULT_IGNORE)
    return {part.strip() for part in raw.split(",") if part.strip()}


def classify(payload: Dict[str, Any]) -> Tuple[str, str]:
    """Return (verdict, reason) for one combined check-runs payload.

    `empty` means there were no relevant jobs. The caller decides whether
    that is "CI has not registered yet" or "this push will not get Actions".
    """
    if "check_runs" not in payload:
        message = str(payload.get("message") or "missing check_runs")
        return "unknown", "unexpected payload: %s" % message[:240]

    latest: Dict[str, Dict[str, Any]] = {}
    skip = ignored_names()
    for run in payload.get("check_runs") or []:
        name = str(run.get("name") or "").strip()
        if not name or name in skip:
            continue
        try:
            run_id = int(run.get("id") or 0)
        except (TypeError, ValueError):
            run_id = 0
        previous = latest.get(name)
        if previous is None or run_id >= int(previous.get("id") or 0):
            latest[name] = run

    if not latest:
        return "empty", "no relevant check runs"

    bad: List[str] = []
    pending: List[str] = []
    for name in sorted(latest):
        run = latest[name]
        status = str(run.get("status") or "")
        conclusion = run.get("conclusion") or ""
        conclusion = str(conclusion)
        if status != "completed":
            pending.append("%s=%s" % (name, status or "unknown"))
            continue
        if conclusion in BAD_CONCLUSIONS:
            bad.append("%s=%s" % (name, conclusion))
        elif conclusion not in OK_CONCLUSIONS:
            # An unfamiliar conclusion is not a pass. Try again next tick
            # rather than pinning production to a permanent red.
            pending.append("%s=unknown:%s" % (name, conclusion or status))

    if bad:
        return "red", "failing checks: " + ", ".join(bad + pending)
    if pending:
        return "pending", "waiting on: " + ", ".join(pending)
    return "green", "%d checks green" % len(latest)


def next_url(link_header: Optional[str]) -> Optional[str]:
    if not link_header:
        return None
    for part in link_header.split(","):
        if 'rel="next"' not in part:
            continue
        start = part.find("<")
        end = part.find(">")
        if start != -1 and end != -1 and end > start:
            return part[start + 1 : end]
    return None


def _api_base() -> str:
    return os.environ.get("BIZBLASTS_GITHUB_API", "https://api.github.com").rstrip("/")


def _repo() -> str:
    return os.environ.get("BIZBLASTS_GITHUB_REPO", DEFAULT_REPO).strip("/")


def _timeout() -> float:
    raw = os.environ.get("BIZBLASTS_GITHUB_API_TIMEOUT", "20")
    try:
        return float(raw)
    except ValueError:
        return 20.0


def fetch_check_runs(sha: str) -> Tuple[str, str]:
    if not SHA_RE.fullmatch(sha):
        return "unknown", "refusing non-sha ref"

    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "bizblasts-deploy-catchup",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = "Bearer " + token

    url: Optional[str] = "%s/repos/%s/commits/%s/check-runs?per_page=100" % (
        _api_base(),
        _repo(),
        sha,
    )
    runs: List[Dict[str, Any]] = []
    total: Optional[int] = None
    pages = 0
    while url and pages < MAX_PAGES:
        request = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=_timeout()) as response:
                body = json.load(response)
                link = response.headers.get("Link")
        except urllib.error.HTTPError as exc:
            return "unknown", "GitHub API HTTP %s" % exc.code
        except Exception as exc:
            # Deliberately omit the exception text: request errors can echo
            # the URL, and we never want a token or query string in the journal.
            return "unknown", "GitHub API error: %s" % type(exc).__name__

        if not isinstance(body, dict) or "check_runs" not in body:
            message = ""
            if isinstance(body, dict):
                message = str(body.get("message") or "")
            return "unknown", "unexpected payload: %s" % (message or "missing check_runs")[:240]

        if total is None:
            try:
                total = int(body.get("total_count"))
            except (TypeError, ValueError):
                total = None
        page_runs = body.get("check_runs") or []
        if not isinstance(page_runs, list):
            return "unknown", "unexpected payload: check_runs is not a list"
        runs.extend(page_runs)
        pages += 1
        url = next_url(link)

    if url:
        return "unknown", "GitHub check-run list truncated after %d pages" % pages
    if total is not None and len(runs) < total:
        return "unknown", "GitHub check-run list incomplete (%d of %d)" % (len(runs), total)

    return classify({"check_runs": runs})


def print_verdict(verdict: str, reason: str) -> None:
    sys.stdout.write(verdict + "\n")
    sys.stdout.write(reason.replace("\n", " ") + "\n")


def main(argv: List[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("sha", nargs="?", help="commit SHA to look up")
    parser.add_argument("--json", help="classify a fixture instead of calling GitHub")
    args = parser.parse_args(argv)

    if args.json:
        try:
            with open(args.json, "r", encoding="utf-8") as handle:
                payload = json.load(handle)
        except (OSError, json.JSONDecodeError) as exc:
            print_verdict("unknown", "could not read check-run JSON: %s" % type(exc).__name__)
            return 2
        if not isinstance(payload, dict):
            print_verdict("unknown", "check-run JSON must be an object")
            return 2
        verdict, reason = classify(payload)
        print_verdict(verdict, reason)
        return 0

    if not args.sha:
        print_verdict("unknown", "usage: deploy_catchup_ci.py SHA | --json FILE")
        return 2

    verdict, reason = fetch_check_runs(args.sha)
    print_verdict(verdict, reason)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
