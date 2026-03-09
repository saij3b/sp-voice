import os

extension Logger {
    private static let subsystem = SPVoiceConstants.logSubsystem

    static let app = Logger(subsystem: subsystem, category: "app")
    static let audio = Logger(subsystem: subsystem, category: "audio")
    static let shortcut = Logger(subsystem: subsystem, category: "shortcut")
    static let provider = Logger(subsystem: subsystem, category: "provider")
    static let transcription = Logger(subsystem: subsystem, category: "transcription")
    static let insertion = Logger(subsystem: subsystem, category: "insertion")
    static let credentials = Logger(subsystem: subsystem, category: "credentials")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let diagnostics = Logger(subsystem: subsystem, category: "diagnostics")
}
