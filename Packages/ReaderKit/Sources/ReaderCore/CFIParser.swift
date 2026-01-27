import Foundation

/// Parsed result from a base EPUB CFI
public struct ParsedCFI: Equatable {
    /// The spine index (0-based)
    public let spineIndex: Int

    /// Optional idref from the CFI
    public let idref: String?

    public init(spineIndex: Int, idref: String? = nil) {
        self.spineIndex = spineIndex
        self.idref = idref
    }
}

/// Parsed result from a full EPUB CFI (including intra-document path)
/// Format: epubcfi(/6/N[idref]!/M/P:C)
/// - /6/N[idref]! - Spine reference (base CFI)
/// - /M/P... - DOM path within spine item (element indices, even numbers per EPUB spec)
/// - :C - Character offset within text node
public struct ParsedFullCFI: Equatable {
    /// The spine index (0-based)
    public let spineIndex: Int

    /// Optional idref from the CFI
    public let idref: String?

    /// DOM path within the spine item (array of element indices, 0-based)
    /// Each index represents a child element position
    public let domPath: [Int]

    /// Optional character offset within the target text node
    public let charOffset: Int?

    public init(spineIndex: Int, idref: String? = nil, domPath: [Int] = [], charOffset: Int? = nil) {
        self.spineIndex = spineIndex
        self.idref = idref
        self.domPath = domPath
        self.charOffset = charOffset
    }
}

/// Parser for EPUB Canonical Fragment Identifiers (CFI)
/// Supports base CFI format for spine-level addressing
///
/// Base CFI format: `epubcfi(/6/N[idref]!)`
/// - /6 refers to the spine element in the OPF package document
/// - N = (spine_index + 1) * 2 (EPUB uses even numbers for spine items)
/// - [idref] is optional and contains the spine item ID reference
/// - ! marks the end of the package document path
public enum CFIParser {

    /// Parse a base CFI string to extract spine index
    ///
    /// Examples:
    /// - `epubcfi(/6/4[pg-header]!)` -> spineIndex: 1
    /// - `epubcfi(/6/2!)` -> spineIndex: 0
    /// - `epubcfi(/6/8[chapter3]!/4/2)` -> spineIndex: 3 (ignores content path after !)
    ///
    /// - Parameter cfi: The CFI string to parse
    /// - Returns: ParsedCFI if valid, nil otherwise
    public static func parseBaseCFI(_ cfi: String) -> ParsedCFI? {
        // Validate basic structure
        guard cfi.hasPrefix("epubcfi(") && cfi.contains(")") else {
            return nil
        }

        // Extract content between epubcfi( and )
        let startIndex = cfi.index(cfi.startIndex, offsetBy: 8) // "epubcfi(" length
        guard let endIndex = cfi.lastIndex(of: ")") else {
            return nil
        }

        let content = String(cfi[startIndex..<endIndex])

        // Parse the path - looking for /6/N pattern
        // The path should start with /6/ for spine reference
        guard content.hasPrefix("/6/") else {
            return nil
        }

        // Extract the spine step number (the N in /6/N)
        let afterSpine = String(content.dropFirst(3)) // Remove "/6/"

        // Find where the step number ends (at [, !, /, or end)
        var numberString = ""
        var idref: String?
        var i = afterSpine.startIndex

        // Extract the number
        while i < afterSpine.endIndex {
            let char = afterSpine[i]
            if char.isNumber {
                numberString.append(char)
            } else {
                break
            }
            i = afterSpine.index(after: i)
        }

        guard let stepNumber = Int(numberString), stepNumber > 0, stepNumber % 2 == 0 else {
            return nil
        }

        // Check for optional idref in brackets [idref]
        if i < afterSpine.endIndex && afterSpine[i] == "[" {
            let bracketStart = afterSpine.index(after: i)
            if let bracketEnd = afterSpine[bracketStart...].firstIndex(of: "]") {
                idref = String(afterSpine[bracketStart..<bracketEnd])
            }
        }

        // Convert step number to spine index: index = (N / 2) - 1
        let spineIndex = (stepNumber / 2) - 1

        return ParsedCFI(spineIndex: spineIndex, idref: idref)
    }

    /// Generate a base CFI for a given spine index
    ///
    /// - Parameters:
    ///   - spineIndex: The 0-based spine index
    ///   - idref: Optional spine item ID reference
    /// - Returns: A CFI string
    public static func generateBaseCFI(spineIndex: Int, idref: String? = nil) -> String {
        // Convert spine index to step number: N = (index + 1) * 2
        let stepNumber = (spineIndex + 1) * 2

        if let idref = idref {
            return "epubcfi(/6/\(stepNumber)[\(idref)]!)"
        } else {
            return "epubcfi(/6/\(stepNumber)!)"
        }
    }

    // MARK: - Full CFI Parsing and Generation

    /// Parse a full CFI string including intra-document path
    ///
    /// Examples:
    /// - `epubcfi(/6/4[ch02]!/4/2/1:42)` -> spineIndex: 1, domPath: [1, 0, 0], charOffset: 42
    /// - `epubcfi(/6/2!/4/2)` -> spineIndex: 0, domPath: [1, 0], charOffset: nil
    ///
    /// - Parameter cfi: The CFI string to parse
    /// - Returns: ParsedFullCFI if valid, nil otherwise
    public static func parseFullCFI(_ cfi: String) -> ParsedFullCFI? {
        // Validate basic structure
        guard cfi.hasPrefix("epubcfi(") && cfi.hasSuffix(")") else {
            return nil
        }

        // Extract content between epubcfi( and )
        let startIndex = cfi.index(cfi.startIndex, offsetBy: 8)
        let endIndex = cfi.index(cfi.endIndex, offsetBy: -1)
        let content = String(cfi[startIndex..<endIndex])

        // Split on ! to separate spine path from content path
        let parts = content.components(separatedBy: "!")
        guard parts.count >= 1 else { return nil }

        let spinePath = parts[0]
        let contentPath = parts.count > 1 ? parts[1] : ""

        // Parse spine path (/6/N[idref])
        guard spinePath.hasPrefix("/6/") else { return nil }

        let afterSpine = String(spinePath.dropFirst(3))
        var numberString = ""
        var idref: String?
        var i = afterSpine.startIndex

        // Extract the spine step number
        while i < afterSpine.endIndex {
            let char = afterSpine[i]
            if char.isNumber {
                numberString.append(char)
            } else {
                break
            }
            i = afterSpine.index(after: i)
        }

        guard let stepNumber = Int(numberString), stepNumber > 0, stepNumber % 2 == 0 else {
            return nil
        }

        // Check for optional idref
        if i < afterSpine.endIndex && afterSpine[i] == "[" {
            let bracketStart = afterSpine.index(after: i)
            if let bracketEnd = afterSpine[bracketStart...].firstIndex(of: "]") {
                idref = String(afterSpine[bracketStart..<bracketEnd])
            }
        }

        let spineIndex = (stepNumber / 2) - 1

        // Parse content path (/M/P...:C)
        var domPath: [Int] = []
        var charOffset: Int?

        if !contentPath.isEmpty {
            // Split on : to separate path from character offset
            let pathParts = contentPath.components(separatedBy: ":")
            let pathString = pathParts[0]

            // Parse character offset if present
            if pathParts.count > 1, let offset = Int(pathParts[1]) {
                charOffset = offset
            }

            // Parse path steps (/N/M/P...)
            let steps = pathString.components(separatedBy: "/").filter { !$0.isEmpty }
            for step in steps {
                // Extract just the number (step may have assertions like [id])
                var stepNumStr = ""
                for char in step {
                    if char.isNumber {
                        stepNumStr.append(char)
                    } else {
                        break
                    }
                }
                if let stepNum = Int(stepNumStr), stepNum > 0, stepNum % 2 == 0 {
                    // Convert EPUB step (even, 1-based) to 0-based index
                    domPath.append((stepNum / 2) - 1)
                }
            }
        }

        return ParsedFullCFI(spineIndex: spineIndex, idref: idref, domPath: domPath, charOffset: charOffset)
    }

    /// Generate a full CFI string from components
    ///
    /// - Parameters:
    ///   - spineIndex: The 0-based spine index
    ///   - idref: Optional spine item ID reference
    ///   - domPath: Array of 0-based element indices within the document
    ///   - charOffset: Optional character offset within the target text node
    /// - Returns: A full CFI string
    public static func generateFullCFI(
        spineIndex: Int,
        idref: String? = nil,
        domPath: [Int] = [],
        charOffset: Int? = nil
    ) -> String {
        // Generate spine path
        let stepNumber = (spineIndex + 1) * 2
        var cfi = "epubcfi(/6/\(stepNumber)"

        if let idref = idref {
            cfi += "[\(idref)]"
        }

        cfi += "!"

        // Generate content path
        if !domPath.isEmpty {
            for index in domPath {
                // Convert 0-based index to EPUB step (even, 1-based)
                let step = (index + 1) * 2
                cfi += "/\(step)"
            }
        }

        // Add character offset if present
        if let offset = charOffset {
            cfi += ":\(offset)"
        }

        cfi += ")"

        return cfi
    }
}
