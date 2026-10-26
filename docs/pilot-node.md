# CVE Program Reference Archiver

## Summary

This is a pilot program exploring how to archive URL references found in CVE Records.  
**Note:** This repository is in early development and is subject to change.

## Status: Review Required

We are transitioning from **Phase 1** to **Phase 2** and would appreciate feedback.

### Open Tasks
- [ ] Prepare the live environment.
- [ ] Pilot in the live environment (target: ~2025-07-10).
- [ ] Refactor and simplify code (currently fragmented across iterations).
- [ ] Report findings to AWG/QWG.

### Known (Out of Scope)
1. **Authentication**
   - This project runs in an isolated environment. API access is only available via SSH to trusted users.
2. **Process & Controls**
   - Archiving is manual and initiated by trusted users. Deletion or modification of archived assets is not currently supported.

---

## Project Overview

The archiver includes:
- **Two Node.js services:**
  1. `scheduler` — Fastify-based HTTP API that queues archive jobs.
  2. `engine` — Executes archive jobs and manages asset relocation.
- **Infrastructure components:**
  1. [`Amazon S3`](link_here) — For storing and delivering archived resources.
  2. [`PostgreSQL`](link_here) — Tracks jobs, assets, and source domains.
- **Development stack:**
  1. [`Visual Studio Code`](https://code.visualstudio.com/) with DevContainers.
  2. [`Docker Desktop`](https://www.docker.com/products/docker-desktop) for local environments, including:
     - [`MinIO`](https://min.io/) (S3-compatible object storage).
     - [`PostgreSQL`](https://www.postgresql.org/) database.

---

## Documentation

- General documentation: [`docs/`]()
- Rationale and background: [`docs/rationale.md`](rationale.md#background--reference-materials)

---

## Launch Strategy

### Phase 1: Prototype
- Set up a local, isolated foundation (database, S3).
- Use ArchiveBox to generate archives and metadata.
- Upload to a public S3 bucket.
- Establish basic workflows for submitting CVEs and reviewing operations.

### Phase 2: Pilot
- Deploy to a shared but isolated environment.
- Provide access to stakeholders as needed (no public access).
- Simulate job submissions over time with test plans.
- Evaluate results and iterate.

### Phase 3: TBD
_Reserved._

---

## Development

**Contributions welcome!**  
See [`docs/overview.md`](overview.md) to get started.

Development is containerized via [DevContainers](https://code.visualstudio.com/docs/devcontainers/containers) to ensure a consistent environment. Recommended setup:
- VSCode + DevContainer plugin
- Docker Desktop

---

## Running Locally

1. Clone and open in VSCode.
2. Open the Command Palette (`Ctrl/Cmd + P`) and run:  
   `> Dev Containers: Rebuild and Reopen in Container`
   - This will reopen the project inside the container environment.
   - Let the `Configuring...` terminal run; it watches and rebuilds on changes.
3. Use the integrated terminal:
   - Run both services: `npm run dev`
   - Run individually: `npm run dev:scheduler` or `npm run dev:engine`

<img src="img/dev-loaded.png">

---

## What to Expect

Once running:

1. **Submit a job:**
   ```bash
   curl --location 'http://localhost:8001/api/v1/jobs' \
     --header 'Content-Type: application/json' \
     --data '{ "cve": "CVE-2025-24070" }'
