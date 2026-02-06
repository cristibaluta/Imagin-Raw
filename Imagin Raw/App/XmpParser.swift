//
//  XmpParser.swift
//  Imagin Raw
//
//  Created by Cristian Baluta on 30.01.2026.
//

import Foundation

struct XmpMetadata: Equatable, Hashable {
    let label: String?
    let rating: Int?
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

    static let xmpTemplate = """
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
           xmp:CreatorTool=""
           xmp:ModifyDate="2025-11-02T13:35:36+03:00"
           xmp:CreateDate="2025-11-02T13:35:36+03:00"
           xmp:MetadataDate="2026-02-02T00:43:19+02:00"
           xmp:Label="">
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
            rating: Int(attributes["xmp:Rating"] ?? "0"),
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

    /// Extract the xmp:Rating value specifically
    static func extractRating(from xmpContent: String) -> Int? {
        return Int(extractDescriptionAttributes(from: xmpContent)["xmp:Rating"] ?? "0")
    }

    /// Update or set the rating in XMP content
    static func updateRating(in xmpContent: String, rating: Int) -> String {
        // Always set the rating value (0-5), don't remove the attribute
        return updateXmpAttributeXML(in: xmpContent, attribute: "xmp:Rating", value: "\(rating)")
    }

    /// Update or set the label in XMP content
    static func updateLabel(in xmpContent: String, label: String?) -> String {
        if let label = label, !label.isEmpty {
            return updateXmpAttributeXML(in: xmpContent, attribute: "xmp:Label", value: label)
        } else {
            return removeXmpAttributeXML(from: xmpContent, attribute: "xmp:Label")
        }
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

    /// Update or add an XMP attribute using XML parsing with regex fallback
    private static func updateXmpAttributeXML(in xmpContent: String, attribute: String, value: String) -> String {
        print("🔧 Attempting to update attribute: \(attribute) = \(value)")

        // First try XML parsing
        do {
            let xmlDoc = try XMLDocument(xmlString: xmpContent, options: [.documentTidyXML])

            // Find the rdf:Description element with proper namespace handling
            xmlDoc.rootElement()?.addNamespace(XMLNode.namespace(withName: "rdf", stringValue: "http://www.w3.org/1999/02/22-rdf-syntax-ns#") as! XMLNode)
            xmlDoc.rootElement()?.addNamespace(XMLNode.namespace(withName: "xmp", stringValue: "http://ns.adobe.com/xap/1.0/") as! XMLNode)

            let xpath = "//rdf:Description"
            let nodes = try xmlDoc.nodes(forXPath: xpath)

            guard let descriptionElement = nodes.first as? XMLElement else {
                print("❌ Could not find rdf:Description element, falling back to regex")
                return updateXmpAttributeRegex(in: xmpContent, attribute: attribute, value: value)
            }

            print("✅ Found rdf:Description element")

            // Remove existing attribute if present
            if let existingAttr = descriptionElement.attribute(forName: attribute) {
                descriptionElement.removeAttribute(forName: attribute)
                print("🗑️ Removed existing attribute: \(attribute)")
            }

            // Add the new attribute
            let newAttribute = XMLNode.attribute(withName: attribute, stringValue: value) as! XMLNode
            descriptionElement.addAttribute(newAttribute)
            print("➕ Added attribute: \(attribute) = \(value)")

            // Update MetadataDate
            updateMetadataDate(in: descriptionElement)

            let result = formatXmpContent(xmlDoc.xmlString)
            print("✅ XML update completed successfully")
            return result

        } catch {
            print("❌ XML parsing error: \(error)")
            print("❌ Falling back to regex approach")
            return updateXmpAttributeRegex(in: xmpContent, attribute: attribute, value: value)
        }
    }

    /// Remove an XMP attribute using XML parsing with regex fallback
    private static func removeXmpAttributeXML(from xmpContent: String, attribute: String) -> String {
        print("🗑️ Attempting to remove attribute: \(attribute)")

        // First try XML parsing
        do {
            let xmlDoc = try XMLDocument(xmlString: xmpContent, options: [.documentTidyXML])

            // Find the rdf:Description element with proper namespace handling
            xmlDoc.rootElement()?.addNamespace(XMLNode.namespace(withName: "rdf", stringValue: "http://www.w3.org/1999/02/22-rdf-syntax-ns#") as! XMLNode)
            xmlDoc.rootElement()?.addNamespace(XMLNode.namespace(withName: "xmp", stringValue: "http://ns.adobe.com/xap/1.0/") as! XMLNode)

            let xpath = "//rdf:Description"
            let nodes = try xmlDoc.nodes(forXPath: xpath)

            guard let descriptionElement = nodes.first as? XMLElement else {
                print("❌ Could not find rdf:Description element, falling back to regex")
                return removeXmpAttributeRegex(from: xmpContent, attribute: attribute)
            }

            // Remove the attribute if it exists
            if descriptionElement.attribute(forName: attribute) != nil {
                descriptionElement.removeAttribute(forName: attribute)
                print("✅ Removed attribute: \(attribute)")
            } else {
                print("ℹ️ Attribute \(attribute) not found, nothing to remove")
            }

            // Update MetadataDate
            updateMetadataDate(in: descriptionElement)

            let result = formatXmpContent(xmlDoc.xmlString)
            print("✅ XML removal completed successfully")
            return result

        } catch {
            print("❌ XML parsing error: \(error)")
            print("❌ Falling back to regex approach")
            return removeXmpAttributeRegex(from: xmpContent, attribute: attribute)
        }
    }

    /// Helper method to update MetadataDate
    private static func updateMetadataDate(in element: XMLElement) {
        let currentDate = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        let currentDateString = dateFormatter.string(from: currentDate)

        if let metadataAttr = element.attribute(forName: "xmp:MetadataDate") {
            element.removeAttribute(forName: "xmp:MetadataDate")
        }
        let metadataAttribute = XMLNode.attribute(withName: "xmp:MetadataDate", stringValue: currentDateString) as! XMLNode
        element.addAttribute(metadataAttribute)
    }

    /// Regex-based fallback for updating attributes
    private static func updateXmpAttributeRegex(in xmpContent: String, attribute: String, value: String) -> String {
        print("🔄 Using regex approach for attribute: \(attribute)")
        var result = xmpContent

        // Escape the attribute name for regex
        let escapedAttribute = NSRegularExpression.escapedPattern(for: attribute)
        let pattern = "\(escapedAttribute)\\s*=\\s*\"[^\"]*\""

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: result.count)
            if regex.firstMatch(in: result, options: [], range: range) != nil {
                // Replace existing attribute
                result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "\(attribute)=\"\(value)\"")
                print("✅ Updated existing attribute with regex")
            } else {
                // Add new attribute before the closing >
                if let range = result.range(of: "<rdf:Description[^>]*>", options: .regularExpression) {
                    let insertPosition = result.index(before: range.upperBound)
                    result.insert(contentsOf: "\n           \(attribute)=\"\(value)\"", at: insertPosition)
                    print("✅ Added new attribute with regex")
                }
            }
        }

        // Update MetadataDate with regex
        updateMetadataDateRegex(in: &result)

        // Format the output for consistent structure
        return formatXmpContent(result)
    }

    /// Regex-based fallback for removing attributes
    private static func removeXmpAttributeRegex(from xmpContent: String, attribute: String) -> String {
        print("🔄 Using regex approach to remove attribute: \(attribute)")
        var result = xmpContent

        // Pattern to match the attribute and its value, including surrounding whitespace
        let escapedAttribute = NSRegularExpression.escapedPattern(for: attribute)
        let pattern = "\\s*\(escapedAttribute)\\s*=\\s*\"[^\"]*\""

        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: result.count)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "")
            print("✅ Removed attribute with regex")
        }

        // Update MetadataDate with regex
        updateMetadataDateRegex(in: &result)

        // Format the output for consistent structure
        return formatXmpContent(result)
    }

    /// Update MetadataDate using regex
    private static func updateMetadataDateRegex(in content: inout String) {
        let currentDate = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        let currentDateString = dateFormatter.string(from: currentDate)

        let pattern = "xmp:MetadataDate\\s*=\\s*\"[^\"]*\""
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(location: 0, length: content.count)
            content = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "xmp:MetadataDate=\"\(currentDateString)\"")
        }
    }

    /// Format XMP content with proper indentation and line breaks
    private static func formatXmpContent(_ xmpContent: String) -> String {
        do {
            let xmlDoc = try XMLDocument(xmlString: xmpContent, options: [.nodePreserveWhitespace])

            // Configure formatting options
            xmlDoc.characterEncoding = "UTF-8"
            xmlDoc.isStandalone = false

            // Format with pretty printing
            let formattedXML = xmlDoc.xmlString(options: [.nodePrettyPrint])

            // Additional custom formatting for better attribute layout
            return formatAttributes(in: formattedXML)

        } catch {
            print("❌ XML formatting error: \(error), returning original content")
            return xmpContent
        }
    }

    /// Format attributes in rdf:Description to have each attribute on a new line
    private static func formatAttributes(in xmlString: String) -> String {
        var result = xmlString

        // Find the rdf:Description tag and format its attributes
        let descriptionPattern = "(<rdf:Description[^>]*>)"

        if let regex = try? NSRegularExpression(pattern: descriptionPattern, options: [.dotMatchesLineSeparators]) {
            let range = NSRange(location: 0, length: result.count)

            if let match = regex.firstMatch(in: result, options: [], range: range),
               let matchRange = Range(match.range, in: result) {

                let descriptionTag = String(result[matchRange])
                let formattedTag = formatDescriptionTag(descriptionTag)
                result.replaceSubrange(matchRange, with: formattedTag)
            }
        }

        return result
    }

    /// Format the rdf:Description tag with proper attribute indentation
    private static func formatDescriptionTag(_ tag: String) -> String {
        // Extract the tag name and attributes
        let tagStartPattern = "<rdf:Description"
        let attributePattern = "\\s+(\\w+:[\\w]+)\\s*=\\s*\"([^\"]*)\""

        var result = "<rdf:Description rdf:about=\"\""
        var attributes: [(String, String)] = []

        // Extract all attributes
        if let attributeRegex = try? NSRegularExpression(pattern: attributePattern, options: []) {
            let range = NSRange(location: 0, length: tag.count)
            attributeRegex.enumerateMatches(in: tag, options: [], range: range) { match, _, _ in
                guard let match = match,
                      let keyRange = Range(match.range(at: 1), in: tag),
                      let valueRange = Range(match.range(at: 2), in: tag) else {
                    return
                }

                let key = String(tag[keyRange])
                let value = String(tag[valueRange])

                // Skip rdf:about as we already added it
                if key != "rdf:about" {
                    attributes.append((key, value))
                }
            }
        }

        // Sort attributes for consistent output (xmlns first, then xmp attributes)
        attributes.sort { (attr1, attr2) in
            let (key1, _) = attr1
            let (key2, _) = attr2

            // xmlns attributes first
            if key1.hasPrefix("xmlns:") && !key2.hasPrefix("xmlns:") {
                return true
            } else if !key1.hasPrefix("xmlns:") && key2.hasPrefix("xmlns:") {
                return false
            }

            // Then alphabetical
            return key1 < key2
        }

        // Add formatted attributes
        for (key, value) in attributes {
            result += "\n            \(key)=\"\(value)\""
        }

        result += ">"

        return result
    }

    /// Create a new XMP file with the given rating and label using the template
    static func createXmpContent(rating: Int = 0, label: String? = nil) -> String {
        var content = xmpTemplate

        // Always set the rating (even if 0)
        content = updateXmpAttributeXML(in: content, attribute: "xmp:Rating", value: "\(rating)")

        // Handle label: set if provided, remove if not
        if let label = label, !label.isEmpty {
            content = updateXmpAttributeXML(in: content, attribute: "xmp:Label", value: label)
        } else {
            // Remove the empty label attribute from template
            content = removeXmpAttributeXML(from: content, attribute: "xmp:Label")
        }

        // Update xmp:MetadataDate with current date
        let currentDate = Date()
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        let currentDateString = dateFormatter.string(from: currentDate)
        content = updateXmpAttributeXML(in: content, attribute: "xmp:MetadataDate", value: currentDateString)

        return content
    }
}
