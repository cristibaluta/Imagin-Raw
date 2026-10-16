# HDR images on Apple platforms

## 1. What "HDR image" means

A normal (SDR) image stores pixel values in 0.0–1.0, where 1.0 is "paper white" (about 100–200 nits on a
display). An HDR image can describe brightness **above** paper white (highlights, speculars, sky, lights).
The extra range is called *headroom*: headroom 4.0 means the brightest pixel is 4× paper white.

There are three common ways files carry HDR:

| Kind | How it works | Typical files |
|------|--------------|---------------|
| **Gain map (adaptive HDR)** | An ordinary SDR image + a second, smaller grayscale "gain map" image. `HDR = SDR × 2^(gain × headroom)`. Old viewers show the SDR base, new viewers apply the map. | iPhone HEIC/JPEG, Google Ultra HDR JPEG, Sony/Canon/Nikon HEIF/JPEG with gain map, JPEG XL |
| **PQ / HLG transfer function** | The image itself is 10/12-bit with a BT.2100 transfer curve (PQ = SMPTE ST 2084, or HLG) in Rec.2020 or P3. No second image. | Sony/Canon HIF, 10-bit HEIC, AVIF, JPEG XL, some PNG/TIFF |
| **Float / extended range** | 16-bit float pixels, values may exceed 1.0 (and go negative) in an "extended" color space. | OpenEXR, 16-bit TIFF, in-memory CGImage after decoding |

The gain map has two flavors:
- **Apple HDRGainMap** (`kCGImageAuxiliaryDataTypeHDRGainMap`): iPhone, older Apple format. The headroom is in Apple's maker note / aux metadata.
- **ISO 21496-1** (`kCGImageAuxiliaryDataTypeISOGainMap`, macOS 15 / iOS 18+): the standardized format, used by Android, Ultra HDR, and new cameras.

## 2. Detecting HDR

Check in this order (cheap → expensive). See `FilesExtensions.hasGainMap(at:)`.

1. **Gain map aux data**
   ```swift
   let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
   CGImageSourceCopyAuxiliaryDataInfoAtIndex(src, 0, kCGImageAuxiliaryDataTypeHDRGainMap) != nil
   CGImageSourceCopyAuxiliaryDataInfoAtIndex(src, 0, kCGImageAuxiliaryDataTypeISOGainMap) != nil // macOS 15+
   ```
2. **PQ/HLG color space** – decode a tiny thumbnail and ask the color space:
   ```swift
   CGColorSpaceUsesITUR_2100TF(cgImage.colorSpace!)   // true for PQ and HLG
   ```
   Or check the ICC profile name / `kCGImagePropertyProfileName` for "PQ", "HLG", "2100".
3. **Extended range**: `CGColorSpaceUsesExtendedRange(cs)`, or `cgImage.bitsPerComponent == 16 && bitmapInfo has floatComponents`.

Notes / pitfalls
- RAW files never contain a gain map. Only the developed companion (JPEG/HEIC/HIF) does, so the check must run on the companion URL.
- Some decoders (notably JPEG with MPF gain maps) don't expose the aux data to `CopyAuxiliaryDataInfo`
  even though Preview shows HDR. In that case check `CGImageSourceCopyPropertiesAtIndex` for
  `kCGImagePropertyHasHDRGainMap`-style keys / the MakerApple dictionary, or just try decoding
  to HDR and see if the result has pixels > 1.0.
- The most reliable test is empirical: decode with the HDR option and compute the max pixel value. If it's > 1.0, the image is HDR.

## 3. Decoding

Goal: produce a `CGImage` whose pixels are **extended-range floats** in an extended color space, so values > 1.0
survive. Anything that redraws into an 8-bit `CGContext` (e.g. `normalizeToSRGB`, `applyingOrientation` via
CGContext, `bitmapRepresentation()` to JPEG for the cache) **clips everything above 1.0 and destroys HDR**.

### Option A – ImageIO (macOS 15 / iOS 18+)
```swift
let options: [CFString: Any] = [
    kCGImageSourceDecodeRequest: kCGImageSourceDecodeToHDR,
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,   // applies orientation
    kCGImageSourceThumbnailMaxPixelSize: maxSize
]
let hdr = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
```
ImageIO applies the gain map (or the PQ/HLG curve) and returns a float image in an extended (usually
linear or extended Display P3) space. Use `kCGImageSourceDecodeToSDR` for the base image.

### Option B – CoreImage
```swift
let ci = CIImage(contentsOf: url, options: [.expandToHDR: true, .applyOrientationProperty: true])
let cs = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!
let cg = CIContext().createCGImage(ci, from: ci.extent, format: .RGBAh, colorSpace: cs)
```
- Render to a **linear** extended space (`extendedLinearSRGB` / `extendedLinearDisplayP3`) in `.RGBAh`.
  Rendering into a non-linear space such as `extendedSRGB` applies a transfer curve whose result depends on
  the source, which can produce over-bright / burned highlights.
- `.expandToHDR` only applies to gain-map images. For PQ/HLG images CoreImage converts from the file's
  color space to the working space automatically.
- For PQ content you can also do tone mapping explicitly with `CIFilter.toneMapHeadroom` (see §4).

### Common reasons highlights look "burned"
1. HDR values were clipped to 1.0 by an 8-bit redraw or a JPEG cache round-trip.
2. A PQ-encoded image was treated as if it were gamma-encoded (the PQ curve is interpreted as sRGB, so
   everything looks way too bright and washed out). Always keep the real color space attached.
3. The gain map was applied twice (once by the decoder, once by `expandToHDR`).
4. The destination view isn't allowed to show EDR, so values > 1.0 are hard-clipped.
5. The image is HDR-decoded but the display can't show it and nobody tone-mapped it (see §4).

## 4. Displaying: HDR vs SDR screens

HDR display capability is dynamic. The OS exposes the **current EDR headroom** of each screen:
- `NSScreen.maximumExtendedDynamicRangeColorComponentValue` (current headroom, changes with brightness / ambient)
- `NSScreen.maximumPotentialExtendedDynamicRangeColorComponentValue` (what the panel can do at most)
- `UIScreen.currentEDRHeadroom` / `potentialEDRHeadroom` on iOS.

| Screen | Headroom | What happens to an extended-range image |
|--------|----------|------------------------------------------|
| XDR / HDR display (MacBook Pro, Pro Display XDR, iPhone/iPad Pro) | > 1.0 | Values > 1.0 are shown as real highlights, *if* the view opts in |
| Standard SDR external monitor | 1.0 | Values > 1.0 are **clipped** to white unless tone-mapped |
| XDR display at max brightness | ~1.0 | Same as SDR: no headroom left |

### Opting in (SwiftUI / AppKit)
```swift
Image(nsImage: image)
    .resizable()
    .allowedDynamicRange(.high)      // allow EDR; .standard forces SDR
```
AppKit: `NSImageView.preferredImageDynamicRange = .high`, `CALayer.wantsExtendedDynamicRangeContent = true`,
or `CAMetalLayer` with `pixelFormat = .rgba16Float` + `wantsExtendedDynamicRangeContent = true` +
extended color space.

### Do you need to handle non-HDR screens?
Mostly **no for the OS, yes for the app's decode choices**:

- When the view is `.allowedDynamicRange(.high)` and the display has no headroom, macOS **does the tone
  mapping/clipping itself** for gain-map images (it falls back to the SDR base image). For PQ/HLG sources the
  system tone-maps to the available headroom in most cases, but this is not guaranteed in custom pipelines
  (Core Image, Metal, `CGContext`).
- **You must handle it yourself** when you:
  - render HDR into an 8-bit surface (export, thumbnails, JPEG cache) → decode with
    `kCGImageSourceDecodeToSDR` or tone-map with `CIFilter.toneMapHeadroom(sourceHeadroom:targetHeadroom:)`;
  - use Core Image / Metal directly → read the screen headroom and tone-map to it;
  - move a window between an HDR and an SDR display → observe
    `NSApplication.didChangeScreenParametersNotification` and
    `NSScreen.maximumExtendedDynamicRangeColorComponentValue`, then re-render if needed.
- Recommended policy for Imagin Raw:
  1. Thumbnails / grid: SDR decode (fast, cacheable).
  2. Single-photo preview / zoom / review: HDR decode, uncached, `.allowedDynamicRange(.high)`.
  3. Export / copy / disk cache: SDR (`DecodeToSDR`), unless exporting to an HDR-capable format on purpose.
  4. Optionally gate the HDR path on
     `NSScreen.main?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1 > 1`
     so SDR-only setups skip the more expensive float decode.

## 5. How this maps to the code

| Concern | Location |
|---------|----------|
| Detect HDR once, cache on the item | `LoadExifOperation` → `FilesExtensions.hasGainMap(at:)` → `PhotoItem.hasGainMap` |
| Bypass the 8-bit/JPEG caches for HDR | `PhotoCacheManager.getImage(for:)` |
| Decode to extended-range float | `CoreGraphicsDecoder.decodeGainMapImage(at:maxPixelSize:)` |
| Display with EDR | `ZoomPanView`, `PhotosPreviewView`, `ReviewPhotoCard` (`.allowedDynamicRange(.high)`) |

## 6. Debugging checklist

For a file that looks wrong, log:
- `CGImageSourceGetType` (UTI) and `kCGImagePropertyProfileName` / color space name
- Whether HDRGainMap / ISOGainMap aux data exists and its info dictionary
- Decoded image: `bitsPerComponent`, `bitmapInfo` float flag, `colorSpace.name`, `CGColorSpaceUsesExtendedRange`
- Maximum pixel value of the decoded image (`CIAreaMaximum` filter). If it is ≤ 1.0 the HDR was lost in decoding;
  if it is > 1.0 but the screen shows burned highlights, the problem is in display (view not opted in, or
  clipped by an intermediate 8-bit step).
- Screen headroom at the time of display.

## 7. References
- WWDC23 "Support HDR images in your app"
- WWDC24 "Use HDR for dynamic image experiences in your app"
- Apple: "Applying Apple-format gain maps to HDR images"
- ISO 21496-1 (Gain map metadata), Google Ultra HDR spec
