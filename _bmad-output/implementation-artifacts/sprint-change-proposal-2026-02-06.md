# Sprint Change Proposal

**Date:** 2026-02-06  
**Author:** BMad Master Agent  
**Change Type:** Minor

---

## 1. Issue Summary

**Problem:** GitHub releases lacked detailed build information in their description, making it difficult for users to understand what was included in each release.

**Context:** When builds complete, only the ZIP file and build log are uploaded without contextual metadata.

**Example:** Users downloading `Kernel-stone-basic-nethunter-21754556113-1.zip` had no way to know kernel version, clang version, or build details without examining the ZIP contents.

---

## 2. Impact Analysis

### Epic Impact
- N/A (Infrastructure/automation improvement)

### Story Impact
- Affects release automation story

### Artifact Conflicts
- `.github/workflows/kernel-ci.yml` - Modified GitHub Release step

### Technical Impact
- Release descriptions now include: Device, Kernel version, Clang version, Build time, Variant, Git SHA
- No breaking changes to existing workflow

---

## 3. Recommended Approach

**Chosen:** Direct Adjustment - Add release body with metadata

**Rationale:**
- Minimal change with high value
- No impact on build process
- Uses existing environment variables
- No rollback needed

**Effort:** < 1 hour  
**Risk:** Low  
**Timeline:** Immediate

---

## 4. Detailed Change Proposals

### Change: Add Release Description with Build Metadata

**File:** `.github/workflows/kernel-ci.yml`  
**Section:** GitHub Release step

**OLD:**
```yaml
- name: GitHub Release
  if: env.SUCCESS == '1'
  uses: softprops/action-gh-release@v2
  with:
    tag_name: build-${{ github.run_id }}-${{ github.run_attempt }}
    name: Kernel-${{ inputs.device }} (run ${{ github.run_id }}/${{ github.run_attempt }})
    fail_on_unmatched_files: false
    files: |
      Kernel-*.zip
      kernel/build.log
```

**NEW:**
```yaml
- name: GitHub Release
  if: env.SUCCESS == '1'
  uses: softprops/action-gh-release@v2
  with:
    tag_name: build-${{ github.run_id }}-${{ github.run_attempt }}
    name: Kernel-${{ inputs.device }} (run ${{ github.run_id }}/${{ github.run_attempt }})
    fail_on_unmatched_files: false
    generate_release_notes: false
    body: |
      ## Build Information
      - **Device:** ${{ inputs.device }}
      - **Kernel:** ${{ env.KERNEL_VERSION || 'unknown' }}
      - **Clang:** ${{ env.CLANG_VERSION || 'unknown' }}
      - **Build Time:** ${{ env.BUILD_TIME || '0' }}s
      - **Variant:** ${{ env.ZIP_VARIANT || 'normal' }}
      - **Git SHA:** ${{ github.sha }}

      ## Artifacts
      - Kernel-*.zip
      - build.log
    files: |
      Kernel-*.zip
      kernel/build.log
```

**Rationale:** Adds detailed build metadata to release description for better traceability.

---

## 5. Implementation Handoff

**Scope Classification:** Minor

**Handoff:** Development team for direct implementation

**Status:** ✅ COMPLETED

**Deliverables:**
- ✅ `.github/workflows/kernel-ci.yml` updated
- ✅ YAML syntax validated
- ✅ Change ready for commit

---

## 6. Verification

```bash
# Verify YAML syntax
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/kernel-ci.yml'))" && echo "✓ Valid"
```

---

## Change Log

| Date | Description |
|------|-------------|
| 2026-02-06 | Created sprint change proposal |
| 2026-02-06 | Applied change to kernel-ci.yml |
