//
//  XmpParser.swift
//  Imagin Bridge
//
//  Created by Cristian Baluta on 30.01.2026.
//

import Foundation

struct XmpMetadata: Equatable, Hashable {
    let label: String?
    let creator: String?
    let rights: String?
    let createDate: String?
    let modifyDate: String?
    let cameraModel: String?
    let lens: String?
    let focalLength: String?
    let aperture: String?
    let shutterSpeed: String?
    let iso: String?
    let exposureBias: String?
}

class XmpParser {

    let xmpTemplate = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/" x:xmptk="Adobe XMP Core 7.0-c000 1.000000, 0000/00/00-00:00:00">
         <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <rdf:Description rdf:about=""
            xmlns:xmp="http://ns.adobe.com/xap/1.0/"
            xmlns:tiff="http://ns.adobe.com/tiff/1.0/"
            xmlns:exif="http://ns.adobe.com/exif/1.0/"
            xmlns:dc="http://purl.org/dc/elements/1.1/"
            xmlns:aux="http://ns.adobe.com/exif/1.0/aux/"
            xmlns:exifEX="http://cipa.jp/exif/1.0/"
            xmlns:photoshop="http://ns.adobe.com/photoshop/1.0/"
            xmlns:xmpMM="http://ns.adobe.com/xap/1.0/mm/"
            xmlns:stEvt="http://ns.adobe.com/xap/1.0/sType/ResourceEvent#"
            xmlns:crd="http://ns.adobe.com/camera-raw-defaults/1.0/"
            xmlns:crs="http://ns.adobe.com/camera-raw-settings/1.0/"
           xmp:Rating="0"
           xmp:CreatorTool="ILCE-7M3 v3.00"
           xmp:ModifyDate="2025-11-02T13:35:36+03:00"
           xmp:CreateDate="2025-11-02T13:35:36+03:00"
           xmp:MetadataDate="2026-02-02T00:43:19+02:00"
           xmp:Label="Approved">
          </rdf:Description>
         </rdf:RDF>
        </x:xmpmeta>
        """

    /// Parse XMP content and extract metadata
    static func parseMetadata(from xmpContent: String) -> XmpMetadata? {
        guard !xmpContent.isEmpty else { return nil }
        
        // Extract attributes from the main rdf:Description element
        let attributes = extractDescriptionAttributes(from: xmpContent)
        
        // Extract nested elements (like creator, rights)
        let nestedValues = extractNestedElements(from: xmpContent)
        
        return XmpMetadata(
            label: attributes["xmp:Label"],
            creator: nestedValues["dc:creator"] ?? attributes["dc:creator"],
            rights: nestedValues["dc:rights"] ?? attributes["dc:rights"],
            createDate: attributes["xmp:CreateDate"],
            modifyDate: attributes["xmp:ModifyDate"],
            cameraModel: attributes["tiff:Model"],
            lens: attributes["aux:Lens"],
            focalLength: attributes["exif:FocalLength"],
            aperture: attributes["exif:FNumber"],
            shutterSpeed: attributes["exif:ExposureTime"],
            iso: extractISOValue(from: xmpContent),
            exposureBias: attributes["exif:ExposureBiasValue"]
        )
    }
    
    /// Extract the xmp:Label value specifically
    static func extractLabel(from xmpContent: String) -> String? {
        return extractDescriptionAttributes(from: xmpContent)["xmp:Label"]
    }
    
    // MARK: - Private Methods
    
    private static func extractDescriptionAttributes(from xmpContent: String) -> [String: String] {
        var attributes: [String: String] = [:]
        
        // Find the rdf:Description element
        guard let descriptionRange = xmpContent.range(of: "<rdf:Description") else {
            return attributes
        }
        
        // Find the end of the opening tag
        let fromIndex = descriptionRange.upperBound
        guard let endTagRange = xmpContent[fromIndex...].range(of: ">") else {
            return attributes
        }
        
        // Extract the attributes section
        let attributesString = String(xmpContent[fromIndex..<endTagRange.lowerBound])
        
        // Parse attributes using regex
        let attributePattern = #"(\w+:\w+)\s*=\s*"([^"]*)"#
        let regex = try? NSRegularExpression(pattern: attributePattern, options: [])
        
        let nsString = attributesString as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        regex?.enumerateMatches(in: attributesString, options: [], range: range) { match, _, _ in
            guard let match = match,
                  let keyRange = Range(match.range(at: 1), in: attributesString),
                  let valueRange = Range(match.range(at: 2), in: attributesString) else {
                return
            }
            
            let key = String(attributesString[keyRange])
            let value = String(attributesString[valueRange])
            attributes[key] = value
        }
        
        return attributes
    }
    
    private static func extractNestedElements(from xmpContent: String) -> [String: String] {
        var nestedValues: [String: String] = [:]
        
        // Extract dc:creator
        if let creator = extractNestedTextValue(from: xmpContent, elementName: "dc:creator") {
            nestedValues["dc:creator"] = creator
        }
        
        // Extract dc:rights
        if let rights = extractNestedTextValue(from: xmpContent, elementName: "dc:rights") {
            nestedValues["dc:rights"] = rights
        }
        
        return nestedValues
    }
    
    private static func extractNestedTextValue(from xmpContent: String, elementName: String) -> String? {
        // Look for pattern like <dc:creator><rdf:Seq><rdf:li>VALUE</rdf:li></rdf:Seq></dc:creator>
        let pattern = "<\(elementName)>.*?<rdf:li[^>]*>([^<]+)</rdf:li>.*?</\(elementName)>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        
        let nsString = xmpContent as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        if let match = regex?.firstMatch(in: xmpContent, options: [], range: range),
           let valueRange = Range(match.range(at: 1), in: xmpContent) {
            return String(xmpContent[valueRange])
        }
        
        // Also check for Alt pattern like <dc:rights><rdf:Alt><rdf:li xml:lang="x-default">VALUE</rdf:li></rdf:Alt></dc:rights>
        let altPattern = "<\(elementName)>.*?<rdf:li[^>]*>([^<]+)</rdf:li>.*?</\(elementName)>"
        let altRegex = try? NSRegularExpression(pattern: altPattern, options: [.dotMatchesLineSeparators])
        
        if let match = altRegex?.firstMatch(in: xmpContent, options: [], range: range),
           let valueRange = Range(match.range(at: 1), in: xmpContent) {
            return String(xmpContent[valueRange])
        }
        
        return nil
    }
    
    private static func extractISOValue(from xmpContent: String) -> String? {
        // Extract ISO from <exif:ISOSpeedRatings><rdf:Seq><rdf:li>1250</rdf:li></rdf:Seq></exif:ISOSpeedRatings>
        let pattern = "<exif:ISOSpeedRatings>.*?<rdf:li>([^<]+)</rdf:li>.*?</exif:ISOSpeedRatings>"
        let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        
        let nsString = xmpContent as NSString
        let range = NSRange(location: 0, length: nsString.length)
        
        if let match = regex?.firstMatch(in: xmpContent, options: [], range: range),
           let valueRange = Range(match.range(at: 1), in: xmpContent) {
            return String(xmpContent[valueRange])
        }
        
        return nil
    }
}
