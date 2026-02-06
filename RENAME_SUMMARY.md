# Project Rename: Imagin Bridge → Imagin Raw

## Summary
Successfully renamed the entire Xcode project from "Imagin Bridge" to "Imagin Raw" throughout the codebase.

## Changes Made

### 1. Xcode Project Files
- ✅ Renamed `Imagin Bridge.xcodeproj` → `Imagin Raw.xcodeproj`
- ✅ Updated all references in `project.pbxproj`
- ✅ Updated scheme files (`.xcscheme`)
- ✅ Updated workspace data (`contents.xcworkspacedata`)

### 2. Project Directory
- ✅ Renamed `Imagin Bridge/` → `Imagin Raw/`

### 3. Configuration Files
- ✅ Renamed `Imagin_Bridge.entitlements` → `Imagin_Raw.entitlements`
- ✅ Renamed `Imagin-Bridge-Bridging-Header.h` → `Imagin-Raw-Bridging-Header.h`
- ✅ Updated all references to these files in project configuration

### 4. Bundle Identifier
- ✅ Changed from: `ro.imagin.bridge`
- ✅ Changed to: `ro.imagin.raw`

### 5. Source Code Updates
- ✅ Updated all Swift files (`.swift`)
- ✅ Updated all Objective-C files (`.h`, `.m`, `.mm`)
- ✅ Updated all file headers and comments
- ✅ Updated all references to "Imagin Bridge" → "Imagin Raw"

### 6. Documentation
- ✅ Updated all markdown files (`.md`)
- ✅ Updated bundle identifier references

## Files Modified
- **Project file**: `Imagin Raw.xcodeproj/project.pbxproj`
- **Entitlements**: `Imagin Raw/Imagin_Raw.entitlements`
- **Bridging header**: `Imagin Raw/Imagin-Raw-Bridging-Header.h`
- **All Swift files**: Updated "Imagin Bridge" → "Imagin Raw"
- **All Objective-C files**: Updated "Imagin Bridge" → "Imagin Raw"
- **Documentation**: All `.md` files updated

## Build Status
✅ **BUILD SUCCEEDED** - The renamed project compiles successfully with no errors.

## App Name
The app will now display as **"Imagin Raw"** instead of "Imagin Bridge" in:
- Finder
- Dock
- Application menus
- About dialog

## Bundle Identifier
The new bundle identifier is: **ro.imagin.raw**

This affects:
- App preferences location
- Sandbox container location
- Code signing identity

## Next Steps

### For First Launch After Rename:
1. **Preferences**: User preferences are stored per bundle identifier, so users may need to reconfigure settings
2. **Sandbox**: The sandbox container path will be different (`~/Library/Containers/ro.imagin.raw/`)
3. **Security-Scoped Bookmarks**: May need to re-grant folder access permissions

### Optional: Migration Script
If you want to migrate user data from the old bundle identifier to the new one, you can create a migration script that:
1. Copies preferences from `ro.imagin.bridge` to `ro.imagin.raw`
2. Migrates saved folder bookmarks
3. Copies cache data

## Testing Checklist
- [x] Project builds successfully
- [ ] App launches correctly
- [ ] App name appears as "Imagin Raw" in Finder/Dock
- [ ] Folder bookmarks work (may need re-granting)
- [ ] Thumbnail cache works
- [ ] External drive access works
- [ ] All features function correctly

## Rollback (if needed)
If you need to rollback:
1. Rename `Imagin Raw.xcodeproj` back to `Imagin Bridge.xcodeproj`
2. Rename `Imagin Raw/` folder back to `Imagin Bridge/`
3. Restore the git commit before the rename

Or simply use git to revert:
```bash
git checkout HEAD -- .
```

---
**Rename Date**: February 6, 2026
**Status**: ✅ Complete
