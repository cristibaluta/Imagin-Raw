# Privacy Policy for Imagin Raw

**Last updated: June 4, 2026**

## Overview

Imagin Raw ("the App") is a RAW photo browser and organizer for macOS and iOS. This privacy policy explains how the App handles your information.

**The short version: Imagin Raw does not collect, transmit, or share any personal data. Everything stays on your device.**

---

## Data Collection

**Imagin Raw does not collect any data.** The App has no analytics, no crash reporting services, no advertising SDKs, and no network connectivity. It makes no outbound connections of any kind.

---

## Data Stored Locally on Your Device

The App stores the following data **exclusively on your device** using standard macOS/iOS system storage (UserDefaults):

- **App preferences** — display settings such as grid size, sort order, and export options
- **Folder bookmarks** — security-scoped bookmarks to folders you have explicitly chosen to open, so the App can re-access them after restart without prompting you again
- **Thumbnail cache** — low-resolution previews of your photos, stored locally to speed up browsing. This cache can be deleted at any time from the App's Settings screen

None of this data ever leaves your device.

---

## Photo and File Access

The App accesses photos and files **only when you explicitly grant permission**:

- **File system access (macOS):** You choose which folders to open via the standard system file picker. The App only reads and writes files within folders you have selected.
- **Photo Library access (iOS/macOS):** If you enable Photo Library integration in Settings, the App requests read/write access to your Photos library. This is used solely to display and organize your photos within the App.
- **XMP sidecar files:** When you rate or label a photo, the App writes a small XMP sidecar file (e.g., `IMG_0001.xmp`) alongside the photo in the same folder. This file contains only the rating and label you assigned. No other metadata is written or modified.

The App does **not** upload your photos or files anywhere.

---

## Sandboxing

On macOS, the App runs in the **App Sandbox**, which restricts its file system access to only the folders you have explicitly granted permission to. This is enforced by the operating system.

---

## Third-Party Services

Imagin Raw uses **no third-party services**, SDKs, or frameworks that collect data. There are no embedded advertising networks, analytics tools, or social media integrations.

The App uses the following open-source libraries, which operate entirely on-device and collect no data:

- **LibRaw** — for decoding RAW photo files
- **RCPreferences / RCLog** — lightweight local preferences and logging utilities (no data transmitted)

---

## Children's Privacy

The App does not knowingly collect any information from anyone, including children under the age of 13. Since no data is collected at all, there is nothing to disclose under COPPA or similar regulations.

---

## Changes to This Privacy Policy

If the privacy practices of the App change in a future version, this policy will be updated and the "Last updated" date at the top will be revised. Since the App has no network connectivity, users will see the updated policy the next time they visit this page.

---

## Contact

If you have any questions about this privacy policy, please contact:

**Cristian Baluta**
cristi.baluta gmail.com

---

*This privacy policy applies to Imagin Raw on macOS and iOS.*
