//
//  SurroundViewCaptureParser.swift
//  BetterBlueKit
//
//  The region-independent half of surround-view parsing.
//
//  Every region that ships this feature delivers the same capture: a
//  base64 image, an optional `imageSize` strip descriptor, a coordinate
//  fix, a `yyyyMMddHHmmss` stamp, and open/closed flags for the doors,
//  trunk and mirrors. What actually differs between regions is only
//
//    1. the ENVELOPE around the array of captures — which stays in the
//       client, because that is also where each region's own error
//       handling lives, and
//    2. WHERE inside a capture each field sits.
//
//  This parser owns everything else. A region describes its field
//  locations with an `EntryShape` — a list of candidate key paths per
//  field, tried in order — and hands over the array. The defaults
//  already cover both Hyundai spellings (nested `gpsDetail.coord.lat`
//  and flat `gpsDetail.coordLat`), so a Hyundai-shaped region supplies
//  nothing at all.
//
//  Adding a region is therefore: find the array, name any keys that
//  moved, call `captures(from:)`.
//

import Foundation

public enum SurroundViewCaptureParser {

    // MARK: - Region description

    /// The names a region uses inside its `doorOpen` object.
    public struct DoorKeys: Sendable {
        public var frontLeft: String
        public var frontRight: String
        public var backLeft: String
        public var backRight: String

        public init(
            frontLeft: String = "frontLeft",
            frontRight: String = "frontRight",
            backLeft: String = "backLeft",
            backRight: String = "backRight"
        ) {
            self.frontLeft = frontLeft
            self.frontRight = frontRight
            self.backLeft = backLeft
            self.backRight = backRight
        }
    }

    /// Where each field lives inside one capture entry.
    ///
    /// Every property is a list of candidate key paths, tried in order,
    /// first hit wins. That is what lets one set of defaults serve
    /// regions that disagree: Hyundai USA nests coordinates under
    /// `gpsDetail.coord`, Hyundai Canada puts them flat as
    /// `gpsDetail.coordLat` — listing both means neither region has to
    /// say anything, and a payload carrying only one of them resolves
    /// exactly as its hand-written parser did.
    ///
    /// A path is matched against the entry dictionary, so `["gpsDetail",
    /// "coord", "lat"]` means `entry["gpsDetail"]["coord"]["lat"]`.
    public struct EntryShape: Sendable {
        /// The base64 image. A capture without one is skipped.
        public var image: [[String]]
        /// The `[totalW, totalH, cameraW, cameraH, topDownW, topDownH]`
        /// strip descriptor. Absent is fine — `SurroundViewDecoder.tiles`
        /// then treats the frame as one whole image rather than guessing
        /// a geometry.
        public var imageSize: [[String]]
        /// A bare `yyyyMMddHHmmss` stamp.
        public var timestamp: [[String]]
        public var latitude: [[String]]
        public var longitude: [[String]]
        /// Heading in degrees, 0 = north.
        public var heading: [[String]]
        public var doors: [[String]]
        public var trunkOpen: [[String]]
        public var sideMirrorOpen: [[String]]
        public var doorKeys: DoorKeys

        public init(
            image: [[String]] = [["svmImage"]],
            imageSize: [[String]] = [["imageSize"]],
            timestamp: [[String]] = [["time"], ["gpsDetail", "time"]],
            latitude: [[String]] = [["gpsDetail", "coord", "lat"], ["gpsDetail", "coordLat"]],
            longitude: [[String]] = [["gpsDetail", "coord", "lon"], ["gpsDetail", "coordLon"]],
            heading: [[String]] = [["gpsDetail", "head"]],
            doors: [[String]] = [["doorOpen"]],
            trunkOpen: [[String]] = [["trunkOpen"]],
            sideMirrorOpen: [[String]] = [["sidemirrorOpen"]],
            doorKeys: DoorKeys = DoorKeys()
        ) {
            self.image = image
            self.imageSize = imageSize
            self.timestamp = timestamp
            self.latitude = latitude
            self.longitude = longitude
            self.heading = heading
            self.doors = doors
            self.trunkOpen = trunkOpen
            self.sideMirrorOpen = sideMirrorOpen
            self.doorKeys = doorKeys
        }
    }

    // MARK: - Entry point

    /// Turns a region's array of capture dictionaries into captures,
    /// newest first.
    ///
    /// Entries without a decodable image, or whose image holds no JPEG
    /// frames, are dropped with a log line rather than failing the whole
    /// fetch — one unreadable capture in a history of several should not
    /// cost the user the rest.
    ///
    /// - Parameter apiName: only used to prefix those log lines, so a
    ///   dropped capture is attributable to a region.
    public static func captures(
        from entries: [[String: Any]],
        vin: String,
        shape: EntryShape = EntryShape(),
        apiName: String
    ) -> [SurroundViewCapture] {
        let captures = entries.compactMap { capture(from: $0, vin: vin, shape: shape, apiName: apiName) }

        // Newest first. Every region observed so far already answers in
        // that order, but nothing documents the guarantee.
        return captures.sorted {
            ($0.capturedAt ?? .distantPast) > ($1.capturedAt ?? .distantPast)
        }
    }

    /// Parses one entry, or nil when it carries no usable imagery.
    public static func capture(
        from entry: [String: Any],
        vin: String,
        shape: EntryShape = EntryShape(),
        providerID: String? = nil,
        apiName: String
    ) -> SurroundViewCapture? {
        guard let encoded = value(in: entry, at: shape.image) as? String,
              let imageData = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else {
            BBLogger.debug(.api, "\(apiName): skipping surround view entry without decodable image")
            return nil
        }

        let frames = SurroundViewDecoder.extractJPEGFrames(from: imageData)
        guard !frames.isEmpty else {
            BBLogger.debug(.api, "\(apiName): surround view entry contained no JPEG frames")
            return nil
        }

        let imageSize = (value(in: entry, at: shape.imageSize) as? [Any])?
            .compactMap { extractNumber(from: $0) as Int? } ?? []

        // Pass the frames, not just the count: a region that sends no
        // `imageSize` (Kia's `inquire`) still gets its five camera views,
        // inferred from the strip's own pixel dimensions.
        return metadata(from: entry, vin: vin, shape: shape, providerID: providerID)
            .loaded(frames: frames, tiles: SurroundViewDecoder.tiles(imageSize: imageSize, frames: frames))
    }

    /// Parses one entry's METADATA, without requiring any imagery.
    ///
    /// This is what makes a lazily-loaded gallery possible: a region that
    /// bills imagery per capture (Kia) can list every capture from its
    /// index response and fetch pixels only for the ones actually looked
    /// at. The result reports `isLoaded == false` until it is filled in
    /// with `SurroundViewCapture.loaded(frames:tiles:)`.
    ///
    /// Unlike `capture(from:)` this never returns nil — an entry with no
    /// imagery is exactly the case it exists to describe.
    public static func metadata(
        from entry: [String: Any],
        vin: String,
        shape: EntryShape = EntryShape(),
        providerID: String? = nil
    ) -> SurroundViewCapture {
        SurroundViewCapture(
            vin: vin,
            capturedAt: timestamp(value(in: entry, at: shape.timestamp)),
            location: location(in: entry, shape: shape),
            heading: extractNumber(from: value(in: entry, at: shape.heading)),
            doorOpen: doors(value(in: entry, at: shape.doors) as? [String: Any], keys: shape.doorKeys),
            trunkOpen: flag(value(in: entry, at: shape.trunkOpen)),
            sideMirrorOpen: flag(value(in: entry, at: shape.sideMirrorOpen)),
            frames: [],
            tiles: [],
            providerID: providerID
        )
    }

    // MARK: - Field readers

    /// Walks each candidate key path in turn and returns the first value
    /// present. Explicit nulls count as absent, so a region that reports
    /// `"gpsDetail": null` for a capture taken without a fix falls
    /// through to its next candidate instead of stopping there.
    static func value(in entry: [String: Any], at paths: [[String]]) -> Any? {
        for path in paths where !path.isEmpty {
            var current: Any? = entry
            for key in path {
                guard let dictionary = current as? [String: Any], let next = dictionary[key],
                      !(next is NSNull) else {
                    current = nil
                    break
                }
                current = next
            }
            if let current { return current }
        }
        return nil
    }

    /// Reads a bare `yyyyMMddHHmmss` stamp, e.g. "20260826003935".
    ///
    /// Read as UTC everywhere. Hyundai Canada confirms that reading
    /// against a live capture, and its sibling `offset` field (the
    /// vehicle's local timezone) is deliberately ignored because the app
    /// renders capture times in the *user's* timezone regardless. The
    /// other regions are not independently confirmed — if a real capture
    /// ever shows vehicle-local time here, that region needs its account
    /// offset applied instead of this shared reading.
    static func timestamp(_ value: Any?) -> Date? {
        guard let raw = value as? String, raw.count == 14 else { return nil }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMddHHmmss"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: raw)
    }

    static func location(in entry: [String: Any], shape: EntryShape) -> VehicleStatus.Location? {
        guard let latitude: Double = extractNumber(from: value(in: entry, at: shape.latitude)),
              let longitude: Double = extractNumber(from: value(in: entry, at: shape.longitude)) else {
            return nil
        }

        let location = VehicleStatus.Location(latitude: latitude, longitude: longitude)
        return location.hasCoordinates ? location : nil
    }

    /// Reads an open/closed flag that may arrive as a JSON boolean, as
    /// 0/1, or as a string. Regions mix the encodings even within one
    /// payload — Hyundai Canada's status sends its `doorOpen` entries as
    /// integers but `trunkOpen` / `hoodOpen` as booleans (kia_uvo#1017,
    /// #1190) — so never bet on a bare `as? Bool`.
    ///
    /// Returns nil only when the key is absent entirely, keeping "closed"
    /// and "not reported" distinguishable.
    static func flag(_ value: Any?) -> Bool? {
        guard let value, !(value is NSNull) else { return nil }
        if let bool = value as? Bool { return bool }
        if let number: Int = extractNumber(from: value) { return number != 0 }
        if let string = value as? String {
            return ["true", "1", "y", "yes", "open"].contains(string.lowercased())
        }
        return nil
    }

    static func doors(_ doors: [String: Any]?, keys: DoorKeys) -> VehicleStatus.DoorStatus? {
        guard let doors else { return nil }

        func isOpen(_ key: String) -> Bool {
            flag(doors[key]) ?? false
        }

        return VehicleStatus.DoorStatus(
            frontLeft: isOpen(keys.frontLeft),
            frontRight: isOpen(keys.frontRight),
            backLeft: isOpen(keys.backLeft),
            backRight: isOpen(keys.backRight)
        )
    }
}
