## 0.1.5 (2026-01-31)

### Fix

- use a temporary file on Windows

## 0.1.4 (2026-01-31)

### Fix

- check for OS type earlier and use OS Separator

### Refactor

- nest and rename .versions.json and de-duplicate changelogs

## 0.1.3 (2026-01-31)

## 0.1.2 (2026-01-31)

### Fix

- skip mac binaries on Windows because can't use pcall
- better utilize mise with test-install

### Refactor

- extract inner branch code

## 0.1.1 (2026-01-31)

### Fix

- don't wrap with pcall
- correct module discovery

## 0.1.0 (2026-01-31)

### Feat

- improve error handling
- support overriding the checksum

### Fix

- leverage fallbacks for Windows

### Refactor

- nest top-level files when possible for better organization

## 0.0.0 (2026-01-30)

### Feat

- improve error output on install
- implement version caching
- improve rate-limiting handling
- cleanup and improvements
- Initial mise-postgres-binary

### Fix

- add plugin versioning
- improve hash validation and coverage
- Windows compatibility and CI (#1)

### Refactor

- Windows-specific fixes
