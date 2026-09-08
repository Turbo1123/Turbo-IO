import Foundation

/// Caller-provided display label and raw values, not a Date or icon enum.
/// Official iOS serializes an entry as label: [temperature, icon].
public struct CityWeatherHourlyRawEntry: Equatable, Sendable {
    public let label: String
    public let temperatureRaw: Int64
    public let iconRaw: Int64

    public init(label: String, temperatureRaw: Int64, iconRaw: Int64) {
        self.label = label
        self.temperatureRaw = temperatureRaw
        self.iconRaw = iconRaw
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        WireTextIdentity.matches(lhs.label, rhs.label) &&
        lhs.temperatureRaw == rhs.temperatureRaw && lhs.iconRaw == rhs.iconRaw
    }
}

/// The seven directly recovered iOS weather-item fields. All are explicit and
/// non-null. Description/range may be empty; no missing-value-to-zero fallback.
public struct CityWeatherRawItem: Equatable, Sendable {
    public let location: String
    public let locationID: String
    public let temperatureRaw: Int64
    public let iconRaw: Int64
    public let descriptionRaw: String
    public let temperatureRangeRaw: String
    public let hourly: [CityWeatherHourlyRawEntry]

    public init(location: String, locationID: String, temperatureRaw: Int64,
                iconRaw: Int64, descriptionRaw: String, temperatureRangeRaw: String,
                hourly: [CityWeatherHourlyRawEntry]) {
        self.location = location
        self.locationID = locationID
        self.temperatureRaw = temperatureRaw
        self.iconRaw = iconRaw
        self.descriptionRaw = descriptionRaw
        self.temperatureRangeRaw = temperatureRangeRaw
        self.hourly = hourly
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        WireTextIdentity.matches(lhs.location, rhs.location) &&
        WireTextIdentity.matches(lhs.locationID, rhs.locationID) &&
        lhs.temperatureRaw == rhs.temperatureRaw && lhs.iconRaw == rhs.iconRaw &&
        WireTextIdentity.matches(lhs.descriptionRaw, rhs.descriptionRaw) &&
        WireTextIdentity.matches(lhs.temperatureRangeRaw, rhs.temperatureRangeRaw) &&
        lhs.hourly == rhs.hourly
    }
}

/// A nonempty list is checked during encoding. This is not a city selection or
/// widget configuration update; the host provides IDs, labels and raw timestamp.
public struct SelectedCityWeatherRawUpdate: Equatable, Sendable {
    public let items: [CityWeatherRawItem]
    public let timestampRaw: String

    public init(items: [CityWeatherRawItem], timestampRaw: String) {
        self.items = items
        self.timestampRaw = timestampRaw
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.items == rhs.items && WireTextIdentity.matches(lhs.timestampRaw, rhs.timestampRaw)
    }
}

/// Local strict policies, not evidence that firmware rejects these inputs.
/// Errors deliberately do not include caller IDs, locations or labels.
public enum CityWeatherEncodingError: Error, Equatable, Sendable {
    case emptyCityList
    case duplicateCityIdentifier
    case duplicateHourlyLabel
}

/// Pure App → Launcher/type18 encoder for the recovered iOS success schema.
/// No network/transport, city lookup, date/unit/icon conversion, refresh, clear,
/// response matching, widget selection or statement about lens presentation.
public struct CityWeatherJSONCodec: Sendable {
    public let limits: DisplayPayloadLimits

    public init(limits: DisplayPayloadLimits = .conservative) { self.limits = limits }

    public func encodeUpdate(_ update: SelectedCityWeatherRawUpdate) throws -> DisplayJSONMessage {
        // Finish a bounded preflight before making sets, Foundation dictionaries,
        // nested arrays or encoded Data. Escaping can expand the bounded input;
        // final strict parsing checks actual encoded string/payload bytes too.
        try preflight(update)
        var cityIDs = Set<WireTextIdentity>()
        var items: [[String: Any]] = []
        for item in update.items {
            guard cityIDs.insert(WireTextIdentity(item.locationID)).inserted else {
                throw CityWeatherEncodingError.duplicateCityIdentifier
            }
            var labels = Set<String>()
            var hourly: [String: [Int64]] = [:]
            for entry in item.hourly {
                // Foundation/Swift dictionary keys use canonical equivalence.
                // Reject both exact duplicates and NFC/NFD key collisions;
                // never silently overwrite a distinct UTF-8 label.
                guard labels.insert(entry.label).inserted else {
                    throw CityWeatherEncodingError.duplicateHourlyLabel
                }
                hourly[entry.label] = [entry.temperatureRaw, entry.iconRaw]
            }
            items.append([
                "location": item.location, "location_id": item.locationID,
                "temp": item.temperatureRaw, "icon": item.iconRaw,
                "des": item.descriptionRaw, "temp_range": item.temperatureRangeRaw,
                "hourly": hourly
            ])
        }
        let innerData = try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
        guard innerData.count <= limits.maxStringBytes else {
            throw DisplayPayloadError.stringTooLong
        }
        var innerParser = try StrictJSONParser(data: innerData, limits: limits)
        _ = try innerParser.parse()
        let innerString = String(decoding: innerData, as: UTF8.self)
        let payload = try encodeJSON([
            "value": 0, "mode": 0, "data": innerString, "ts": update.timestampRaw
        ], limits: limits)
        let prefix = Data(#"{"cmd":"weather_update","payload":"#.utf8)
        let suffix = Data("}".utf8)
        guard prefix.count <= limits.maxPayloadBytes,
              suffix.count <= limits.maxPayloadBytes - prefix.count,
              payload.count <= limits.maxPayloadBytes - prefix.count - suffix.count else {
            throw DisplayPayloadError.payloadTooLarge
        }
        var envelope = prefix
        envelope.append(payload)
        envelope.append(suffix)
        _ = try JSONObject(data: envelope, limits: limits)
        return DisplayJSONMessage(type: 18, payload: envelope)
    }

    private func preflight(_ update: SelectedCityWeatherRawUpdate) throws {
        guard !update.items.isEmpty else { throw CityWeatherEncodingError.emptyCityList }
        guard update.items.count <= limits.maxCollectionElements,
              limits.maxCollectionElements >= 7 else {
            throw DisplayPayloadError.excessiveCollection
        }
        guard limits.maxNestingDepth >= 3 else { throw DisplayPayloadError.excessiveNesting }
        try validateIdentifier(update.timestampRaw, key: "ts", limits: limits)
        var budget = CityWeatherMinimumByteBudget(limits: limits)
        try budget.consume(2) // array brackets
        for (index, item) in update.items.enumerated() {
            guard item.hourly.count <= limits.maxCollectionElements else {
                throw DisplayPayloadError.excessiveCollection
            }
            if !item.hourly.isEmpty, limits.maxNestingDepth < 5 {
                throw DisplayPayloadError.excessiveNesting
            }
            try budget.consume(index == 0 ? 0 : 1)
            try budget.consume(2 + 6) // item braces and six field commas
            for key in ["location", "location_id", "temp", "icon", "des", "temp_range", "hourly"] {
                try budget.consume(key.utf8.count + 3) // quotes and colon
            }
            try validateIdentifier(item.location, key: "location", limits: limits)
            try validateIdentifier(item.locationID, key: "location_id", limits: limits)
            for value in [item.location, item.locationID, item.descriptionRaw, item.temperatureRangeRaw] {
                try budget.consumeString(value, limits: limits)
            }
            try budget.consume(String(item.temperatureRaw).utf8.count)
            try budget.consume(String(item.iconRaw).utf8.count)
            try budget.consume(2) // hourly object, including an explicitly empty {}
            for (entryIndex, entry) in item.hourly.enumerated() {
                try validateIdentifier(entry.label, key: "hourly.label", limits: limits)
                try budget.consume(entryIndex == 0 ? 0 : 1)
                try budget.consumeString(entry.label, limits: limits)
                try budget.consume(4) // colon, array brackets and integer separator
                try budget.consume(String(entry.temperatureRaw).utf8.count)
                try budget.consume(String(entry.iconRaw).utf8.count)
            }
        }
    }
}

/// Lower bound including every string, integer, container and punctuation byte.
/// A fail-fast check before building another object graph, not an exact escaped
/// size prediction or permission to return an unchecked Foundation result.
private struct CityWeatherMinimumByteBudget {
    private var remaining: Int
    private let exceeded: DisplayPayloadError

    init(limits: DisplayPayloadLimits) {
        remaining = min(limits.maxPayloadBytes, limits.maxStringBytes)
        exceeded = limits.maxStringBytes <= limits.maxPayloadBytes ? .stringTooLong : .payloadTooLarge
    }

    mutating func consume(_ amount: Int) throws {
        guard amount >= 0, amount <= remaining else { throw exceeded }
        remaining -= amount
    }

    mutating func consumeString(_ value: String, limits: DisplayPayloadLimits) throws {
        guard value.utf8.count <= limits.maxStringBytes else { throw DisplayPayloadError.stringTooLong }
        try consume(value.utf8.count)
        try consume(2)
    }
}
