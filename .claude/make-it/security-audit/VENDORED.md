# Vendored: cloudflare/security-audit-skill

- **Source:** https://github.com/cloudflare/security-audit-skill (`skills/security-audit/`, plus `LICENSE`)
- **Commit:** c1c8a8c1471069fb0e188eeaff69b8e8db6564a8 (2026-09-14)
- **Licence:** MIT, Copyright (c) 2025-2026 Cloudflare, Inc. -- see `LICENSE`
- **Used by:** `/nemo-it` (the deep code audit phase) and `/fix-it` (reads its `findings.json`)

These files are an unmodified copy. Do not edit them: make-it's own rules for the audit live in
`nemo-it.md` and `fix-it.md`. `SHA256SUMS` lists every vendored file; `scripts/test-nemo-audit.sh`
fails if one differs.

To update: copy the new `skills/security-audit/*` and `LICENSE` over these, change the commit above,
regenerate `SHA256SUMS` (`shasum -a 256 <files> > SHA256SUMS`), run `node --test` here, then
`scripts/test-nemo-audit.sh`.
