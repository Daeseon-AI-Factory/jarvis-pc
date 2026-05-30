//
//  Logging.swift
//  ScreenBridge — Phase 2.3
//
//  Unified logging system (os.Logger). Console.app + `log stream` + Xcode console
//  모두 stream. NSLog 대체 (사용자 좌절 흐름 정리, dev UX).
//
//  Stream 명령 (별도 Terminal):
//    log stream --predicate 'subsystem == "com.screenbridge.app"' --info
//

import OSLog

enum Log {
    private static let subsystem = "com.screenbridge.app"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let hotkey = Logger(subsystem: subsystem, category: "hotkey")
    static let panel = Logger(subsystem: subsystem, category: "panel")
    static let dispatcher = Logger(subsystem: subsystem, category: "dispatcher")
}
