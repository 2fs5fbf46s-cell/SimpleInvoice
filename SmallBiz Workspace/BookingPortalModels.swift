import Foundation

struct BookingServiceOption: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var durationMinutes: Int

    enum CodingKeys: String, CodingKey {
        case name
        case durationMinutes
    }
}

enum PortalWeekday: String, CaseIterable, Identifiable, Codable {
    case mon, tue, wed, thu, fri, sat, sun

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mon: return "Mon"
        case .tue: return "Tue"
        case .wed: return "Wed"
        case .thu: return "Thu"
        case .fri: return "Fri"
        case .sat: return "Sat"
        case .sun: return "Sun"
        }
    }
}

struct PortalHoursDay: Codable, Equatable {
    var isOpen: Bool
    var start: String?
    var end: String?
}

struct PortalHoursConfig: Codable, Equatable {
    var days: [PortalWeekday: PortalHoursDay]

    init(days: [PortalWeekday: PortalHoursDay]) {
        self.days = days
    }

    static func defaultClosed() -> PortalHoursConfig {
        var map: [PortalWeekday: PortalHoursDay] = [:]
        for day in PortalWeekday.allCases {
            map[day] = PortalHoursDay(isOpen: false, start: nil, end: nil)
        }
        return PortalHoursConfig(days: map)
    }

    func toBusinessHoursDict() -> [String: [String: String?]] {
        var out: [String: [String: String?]] = [:]
        for day in PortalWeekday.allCases {
            let d = days[day] ?? PortalHoursDay(isOpen: false, start: nil, end: nil)
            if d.isOpen {
                let start = d.start
                let end = d.end
                out[day.rawValue] = [
                    // Include both historical and new keys for backend compatibility.
                    "open": start,
                    "close": end,
                    "start": start,
                    "end": end,
                    "isOpen": "true"
                ]
            } else {
                out[day.rawValue] = [
                    "open": nil,
                    "close": nil,
                    "start": nil,
                    "end": nil,
                    "isOpen": "false"
                ]
            }
        }
        return out
    }

    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let dict = toBusinessHoursDict()
        guard let data = try? encoder.encode(dict) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func fromJSON(_ json: String) -> PortalHoursConfig? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let dict = try? JSONDecoder().decode([String: [String: String?]].self, from: data) else {
            return nil
        }
        return fromBusinessHoursDict(dict)
    }

    static func fromBusinessHoursDict(_ dict: [String: [String: String?]]) -> PortalHoursConfig {
        var out: [PortalWeekday: PortalHoursDay] = [:]
        for day in PortalWeekday.allCases {
            let key = day.rawValue
            let payload = dict[key] ?? [:]
            let openRaw = payload["open"] ?? nil
            let isOpenRaw = payload["isOpen"] ?? nil
            let isOpen: Bool
            if let isOpenRaw {
                isOpen = isOpenRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "true"
            } else if let openRaw {
                let normalized = openRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if normalized == "true" || normalized == "false" {
                    isOpen = normalized == "true"
                } else {
                    // Some payloads use open/close as time strings.
                    isOpen = !normalized.isEmpty
                }
            } else {
                let hasStart = (payload["start"] ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                let hasEnd = (payload["end"] ?? payload["close"] ?? nil)?
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                let hasClose = (payload["close"] ?? nil)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                isOpen = hasStart || hasEnd || hasClose
            }
            let start = payload["start"] ?? payload["open"] ?? nil
            let end = payload["end"] ?? payload["close"] ?? nil
            out[day] = PortalHoursDay(isOpen: isOpen, start: start, end: end)
        }
        return PortalHoursConfig(days: out)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(toBusinessHoursDict())
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let dict = try container.decode([String: [String: String?]].self)
        self = PortalHoursConfig.fromBusinessHoursDict(dict)
    }
}
