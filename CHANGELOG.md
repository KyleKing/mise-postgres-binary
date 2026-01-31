## 0.1.2 (2026-01-31)

### Fix

- skip mac binaries on Windows because can't use pcall
- better utilize mise with test-install

## 0.1.1 (2026-01-31)

### Fix

- don't wrap with pcall
- correct module discovery

## 0.1.0 (2026-01-31)

### Feat

- improve error handling
- support overriding the checksum
- improve error output on install
- implement version caching
- improve rate-limiting handling
- cleanup and improvements
- Initial mise-postgres-binary

### Fix

- leverage fallbacks for Windows
- add plugin versioning
- improve hash validation and coverage
- Windows compatibility and CI (#1)

### Refactor

- nest top-level files when possible for better organization
- Windows-specific fixes
