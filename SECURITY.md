# Security policy

Report vulnerabilities in this tap privately. Do not open a public issue.

- GitHub: open the Security tab of this repository and choose "Report a vulnerability"
  ([direct link](https://github.com/protocortex/homebrew-tap/security/advisories/new)).
- Email: security@protocortex.ai

This tap only holds the Homebrew formula for LIAM. A flaw in LIAM itself belongs in the
[LIAM security policy](https://github.com/protocortex/liam/blob/main/SECURITY.md).

Only the latest release of LIAM, and the formula that installs it, is supported.

## What the formula trusts

The stable formula downloads one prebuilt archive from a GitHub release of `protocortex/liam` and
checks it against the sha256 in the formula. A release pull request writes that sha256 from the
release's own `SHA256SUMS`. The HEAD build compiles `protocortex/liam` main from source.
