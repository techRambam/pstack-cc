---
name: research
description: Use for "best practices", "baseline", "state of the art", "exhaustive" or "many sources" research, "research X and save it", and docs or API facts. Reads primary sources as saved full text, checks every quote with a script, and saves a cited Markdown note.
---

Spin up a **background agent** to do the research, so you keep working while it reads.

Its job:

1. Investigate the question against **primary sources** (official docs, source code, specs, first-party APIs), not a secondary write-up of them. Download each source and read the saved full text, never a WebFetch result, which is another model's summary of the page. List a source you cannot save as unread, and cite no claim to it. Follow every claim back to the source that owns it. Never call any service with credentials you invented or were not given. Never call a live production or payment endpoint unless the brief names that exact endpoint.
2. Write the findings to a single Markdown file, citing each claim's source. Check every quoted claim: write and run a script that finds each quote, with whitespace collapsed, in the saved file of the source it cites. Fix or drop a quote it cannot find, and report how many quotes it checked and how many failed.
3. Save it where the repo already keeps such notes; match the existing convention, and if there is none, put it somewhere sensible and say where.
