# Security policy

Propscope is a self-hosted app that stores your API keys (encrypted) in your own database, so security reports matter.

## Reporting a vulnerability

Please **don't open a public issue**. Use GitHub's private reporting instead: go to the repository's **Security** tab and choose **Report a vulnerability**. Include what you found, how to reproduce it, and the version (Settings, About).

I'll acknowledge reports as soon as I can and credit you in the fix unless you'd rather not be named.

## Scope

In scope: the Rails app, the optional model service, the Docker setup, and anything that could leak API keys or let someone reach a self-hosted copy that shouldn't.

Out of scope: problems in third-party providers, or exposing your own instance to the internet in single-user mode (it has no sign-in by design; see [docs/self-hosting.md](docs/self-hosting.md)).

## Good practice for your own copy

- Keep the default `127.0.0.1` binding. If other machines need to reach it, set `SINGLE_USER=false` so accounts are on.
- Keep `.env` out of version control (it's already in `.gitignore`).
