#!/usr/bin/env python3
"""Resolve a ROOTFS_VERSION value to the job ID of the latest successful build-rootfs-job.

Usage: python3 resolve-rootfs-version.py <rootfs_version>
  'latest'          — finds the most recent successful build-rootfs-job on a vX.Y.Z tag.
  '<branch_or_tag>' — finds the most recent successful build-rootfs-job for that ref.

Prints the job ID to stdout.

Requires environment variables: CI_API_V4_URL, CI_LEPTON_TOKEN
"""
import json, os, re, sys, urllib.parse, urllib.request

PROJECT = "deckard%2Flepton"

def _api_get(api_url: str, token: str, path: str) -> list:
    url = f"{api_url}/projects/{PROJECT}/{path}"
    req = urllib.request.Request(url, headers={"PRIVATE-TOKEN": token})
    with urllib.request.urlopen(req) as resp:
        return json.loads(resp.read())

def _resolve_latest(api_url: str, token: str, job_name: str) -> int:
    # List tags sorted by date descending, then find the first one whose
    # commit has a pipeline with a successful build-rootfs-job.
    tags = _api_get(api_url, token,
        "repository/tags?per_page=100")
    tags = [tag for tag in tags
            if re.match(r"^v\d+\.\d+\.\d+$", tag["name"])]
    tags.sort(
        key=lambda tag: tuple(map(int, tag["name"][1:].split("."))),
        reverse=True,
    )

    for tag in tags:
        sha = tag["commit"]["id"]
        pipelines = _api_get(api_url, token, f"pipelines?sha={sha}&per_page=5")
        for pipeline in pipelines:
            jobs = _api_get(api_url, token, f"pipelines/{pipeline['id']}/jobs?per_page=100")
            for job in jobs:
                if job["name"] == job_name and job["status"] == "success":
                    print(f"Resolved ROOTFS_VERSION=latest to: {tag['name']} "
                          f"(job {job['id']}, pipeline {pipeline['id']})", file=sys.stderr)
                    return job["id"]

    print(f"ERROR: no successful {job_name} found for any vX.Y.Z tag", file=sys.stderr)
    sys.exit(1)

def _resolve_ref(api_url: str, token: str, ref: str, job_name: str) -> int:
    encoded_ref = urllib.parse.quote(ref, safe="")
    pipelines = _api_get(api_url, token,
        f"pipelines?ref={encoded_ref}&per_page=20")

    for pipeline in pipelines:
        jobs = _api_get(api_url, token, f"pipelines/{pipeline['id']}/jobs?per_page=100")
        for job in jobs:
            if job["name"] == job_name and job["status"] == "success":
                print(f"Resolved ROOTFS_VERSION={ref} to job {job['id']} "
                      f"(pipeline {pipeline['id']})", file=sys.stderr)
                return job["id"]

    print(f"ERROR: no successful {job_name} found for ref '{ref}'", file=sys.stderr)
    sys.exit(1)

def resolve(job_name: str, rootfs_version: str) -> int:
    api_url = os.environ["CI_API_V4_URL"]
    token = os.environ["CI_LEPTON_TOKEN"]

    if rootfs_version == "latest":
        return _resolve_latest(api_url, token, job_name)
    return _resolve_ref(api_url, token, job_name, rootfs_version)

if __name__ == "__main__":
    if len(sys.argv) != 3 or not sys.argv[1]:
        print("Usage: resolve-rootfs-version.py <android build job> <rootfs_version>", file=sys.stderr)
        sys.exit(1)
    print(resolve(sys.argv[1], sys.argv[2]))
