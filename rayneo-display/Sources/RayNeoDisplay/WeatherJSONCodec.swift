import Foundation

/// Explicit raw weather values; no Celsius/Fahrenheit or icon-name mapping is
/// implied. Timestamp is the caller's wire String, not a Date or monotonic tick.
/// This only represents the observed successful current-location data shape.
public struct CurrentWeatherRawUpdate: Equatable, Sendable {
    public let location: String
    public let temperatureRaw: Int64
    public let iconRaw: Int64
    public let timestampRaw: String

    public init(location: String, temperatureRaw: Int64, iconRaw: Int64,
                timestampRaw: String) {
        self.location = location
        self.temperatureRaw = temperatureRaw
        self.iconRaw = iconRaw
        self.timestampRaw = timestampRaw
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        WireTextIdentity.matches(lhs.location, rhs.location) &&
        lhs.temperatureRaw == rhs.temperatureRaw && lhs.iconRaw == rhs.iconRaw &&
        WireTextIdentity.matches(lhs.timestampRaw, rhs.timestampRaw)
    }
}

/// An observed response with an un-interpreted integer result. Even value 0 has
/// no request ID or timestamp and cannot complete the latest request or prove
/// the content was applied/displayed. Unknown fields remain in originalPayload.
public struct WeatherResponseObserved: Equatable, Sendable {
    public let command: WeatherUpdateCommand
    public let valueRaw: Int64
    public let originalPayload: Data
}

/// Distinct content update commands. Neither one is a dashboard configuration
/// response or a glasses-initiated request for fresh weather data.
public enum WeatherUpdateCommand: String, CaseIterable, Sendable {
    case currentLocation = "current_weather_update"
    case selectedCities = "weather_update"
}

public enum WeatherGlassesMessage: Equatable, Sendable {
    case responseObserved(WeatherResponseObserved)
    case unknown(businessRawValue: UInt16, type: UInt16, payload: Data)
}

/// iOS 1.0.2(67) current-weather encoder plus two tagged update observations.
/// Shared response fields have direct iOS static evidence; the selected-city
/// runtime log retained its success marker, not a full original response JSON.
/// It cannot select a city, fetch weather, generate timestamps, clear a widget,
/// send a packet, associate an ACK with a request, or inspect a glasses display.
public struct WeatherJSONCodec: Sendable {
    /// Explicit iOS BusinessID raw, not an assumed enum index. The host remains
    /// responsible for establishing a legitimate transport and routing context.
    public static let launcherBusinessRawValue: UInt16 = 15
    public let limits: DisplayPayloadLimits

    public init(limits: DisplayPayloadLimits = .conservative) { self.limits = limits }

    /// App → Launcher/type 18. All required values are explicit and non-null.
    /// Rejecting blank location/timestamp and requiring integers is our strict
    /// local subset, not a discovered firmware restriction or weather validation.
    public func encodeCurrentWeatherUpdate(_ update: CurrentWeatherRawUpdate) throws -> DisplayJSONMessage {
        try validateIdentifier(update.location, key: "location", limits: limits)
        try validateIdentifier(update.timestampRaw, key: "ts", limits: limits)
        let innerData = try encodeJSON([
            "location": update.location, "icon": update.iconRaw,
            "temp": update.temperatureRaw
        ], limits: limits)
        // Bound before allocating the String passed into the outer JSON layer.
        guard innerData.count <= limits.maxStringBytes else {
            throw DisplayPayloadError.stringTooLong
        }
        let innerString = String(decoding: innerData, as: UTF8.self)
        let payload = try encodeJSON([
            "value": 0, "mode": 0, "data": innerString, "ts": update.timestampRaw
        ], limits: limits)

        // Existing encodeJSON deliberately accepts only flat known objects.
        // Assemble this one fixed nested envelope from already validated JSON;
        // no unescaped caller text is interpolated into the JSON syntax.
        let prefix = Data(#"{"cmd":"current_weather_update","payload":"#.utf8)
        let suffix = Data("}".utf8)
        guard prefix.count <= limits.maxPayloadBytes,
              suffix.count <= limits.maxPayloadBytes - prefix.count,
              payload.count <= limits.maxPayloadBytes - prefix.count - suffix.count else {
            throw DisplayPayloadError.payloadTooLarge
        }
        var envelope = prefix
        envelope.append(payload)
        envelope.append(suffix)
        // Validate full nesting, keys and escaped string limits as well. The
        // inner JSON String is intentionally not flattened into an object.
        _ = try JSONObject(data: envelope, limits: limits)
        return DisplayJSONMessage(type: 18, payload: envelope)
    }

    /// Glasses → Launcher/type 19 only. The business value comes from the host's
    /// actual routed message, not from untrusted JSON or a newly stamped epoch.
    /// Wrong routes/types remain bounded unknown bytes; no schema is guessed.
    public func decodeGlassesResponse(businessRawValue: UInt16, type: UInt16,
                                      payload: Data) throws -> WeatherGlassesMessage {
        try limits.checkSize(payload)
        guard businessRawValue == Self.launcherBusinessRawValue, type == 19 else {
            return .unknown(businessRawValue: businessRawValue, type: type, payload: payload)
        }
        let envelope = try JSONObject(data: payload, limits: limits)
        guard let commandValue = envelope.fields["cmd"] else {
            throw DisplayPayloadError.missingField("cmd")
        }
        guard case .string(let command) = commandValue else {
            throw DisplayPayloadError.wrongType("cmd")
        }
        let updateCommand: WeatherUpdateCommand
        if WireTextIdentity.matches(command, WeatherUpdateCommand.currentLocation.rawValue) {
            updateCommand = .currentLocation
        } else if WireTextIdentity.matches(command, WeatherUpdateCommand.selectedCities.rawValue) {
            updateCommand = .selectedCities
        } else {
            // Request/config and unknown commands never become update events.
            return .unknown(businessRawValue: businessRawValue, type: type, payload: payload)
        }
        guard let payloadValue = envelope.fields["payload"] else {
            throw DisplayPayloadError.missingField("payload")
        }
        let fields = try JSONObject(payloadValue)
        let rawValue = try fields.int("value")
        return .responseObserved(WeatherResponseObserved(
            command: updateCommand, valueRaw: rawValue, originalPayload: payload
        ))
    }
}
