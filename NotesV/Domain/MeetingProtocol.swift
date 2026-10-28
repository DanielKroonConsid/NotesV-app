import Foundation

/// The content of a meeting protocol, as returned by an AI provider.
///
/// Every provider must return this structure (see `jsonSchema`), so all providers produce the same
/// protocol. The meeting info itself comes from `MeetingDetails`, not from the AI, so it can't be invented.
struct MeetingProtocol: Hashable, Sendable, Codable {
    struct AgendaItem: Hashable, Sendable, Codable {
        var title: String
        var summary: String
    }

    struct ActionItem: Hashable, Sendable, Codable {
        var task: String
        var owner: String?
        var dueDate: String?
    }

    /// The ISO 639-1 code of the language the protocol is written in, e.g. "sv".
    var language: String
    var attendeesPresent: [String]
    var attendeesAbsent: [String]
    var agendaItems: [AgendaItem]
    var decisions: [String]
    var actionItems: [ActionItem]

    init(
        language: String,
        attendeesPresent: [String] = [],
        attendeesAbsent: [String] = [],
        agendaItems: [AgendaItem] = [],
        decisions: [String] = [],
        actionItems: [ActionItem] = []
    ) {
        self.language = language
        self.attendeesPresent = attendeesPresent
        self.attendeesAbsent = attendeesAbsent
        self.agendaItems = agendaItems
        self.decisions = decisions
        self.actionItems = actionItems
    }

    /// Missing lists decode as empty, because providers without strict JSON schemas may leave them out.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "en"
        attendeesPresent = try container.decodeIfPresent([String].self, forKey: .attendeesPresent) ?? []
        attendeesAbsent = try container.decodeIfPresent([String].self, forKey: .attendeesAbsent) ?? []
        agendaItems = try container.decodeIfPresent([AgendaItem].self, forKey: .agendaItems) ?? []
        decisions = try container.decodeIfPresent([String].self, forKey: .decisions) ?? []
        actionItems = try container.decodeIfPresent([ActionItem].self, forKey: .actionItems) ?? []
    }

    /// The JSON schema of this structure, in the strict form OpenAI-style structured outputs require:
    /// every property is required, optional values are nullable, and no extra properties are allowed.
    static let jsonSchema: JSONValue = [
        "type": "object",
        "additionalProperties": false,
        "required": ["language", "attendeesPresent", "attendeesAbsent", "agendaItems", "decisions", "actionItems"],
        "properties": [
            "language": ["type": "string", "description": "ISO 639-1 code of the language the protocol is written in."],
            "attendeesPresent": ["type": "array", "items": ["type": "string"]],
            "attendeesAbsent": ["type": "array", "items": ["type": "string"]],
            "agendaItems": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["title", "summary"],
                    "properties": [
                        "title": ["type": "string"],
                        "summary": ["type": "string"],
                    ],
                ],
            ],
            "decisions": ["type": "array", "items": ["type": "string"]],
            "actionItems": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": ["task", "owner", "dueDate"],
                    "properties": [
                        "task": ["type": "string"],
                        "owner": ["type": ["string", "null"]],
                        "dueDate": ["type": ["string", "null"]],
                    ],
                ],
            ],
        ],
    ]
}
