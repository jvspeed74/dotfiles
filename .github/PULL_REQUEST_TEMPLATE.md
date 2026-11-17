## Summary

<!-- 1-3 sentences: what changed and why. -->

## Test plan

Bootstrap CI does not run on PR pushes. Run the checks locally and append each outcome under
**Results**. Tested commit SHA: `<sha>`

- [ ] `.github/ci/templates.sh` (needs chezmoi)
- [ ] `UBUNTU_VERSION=24.04 .github/ci/run-bootstrap.sh personal` (needs Docker)
- [ ] `UBUNTU_VERSION=24.04 .github/ci/run-bootstrap.sh corporate`
- [ ] `UBUNTU_VERSION=26.04 .github/ci/run-bootstrap.sh personal`
- [ ] `UBUNTU_VERSION=26.04 .github/ci/run-bootstrap.sh corporate`
- [ ] `.github/ci/docs.sh` (needs Docker and python3)

Optional remote run: `gh workflow run bootstrap.yml --ref <branch>`

### Results

<!-- Append one entry per command as it is run, newest last. Never overwrite an earlier entry.
     Record: command, exit status, and the final lines or the PASS/FAIL counts. -->
