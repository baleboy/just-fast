//
//  AppContainer.swift
//  Fastino
//
//  The shared SwiftData ModelContainer, used by the app and by App Intents so
//  every surface writes through the same store (§4.6, §7).
//
//  CloudKit note: the spec calls for CloudKit private-database sync (§3). That
//  requires a real iCloud container id declared in Fastino.entitlements
//  (`iCloud.com.balenet.fastino`) and matching provisioning. To keep the app
//  buildable and launchable everywhere out of the box, persistence defaults to
//  local-only (`.none`). Flip `cloudKitDatabase` to `.automatic` and fill in the
//  entitlement's container identifier to enable sync — the schema is already
//  CloudKit-compatible (all attributes defaulted, no unique constraints).
//

import Foundation
import SwiftData

enum AppContainer {
    static let schema = Schema([Fast.self, AppSettings.self])

    static let shared: ModelContainer = {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none // → .automatic to enable CloudKit sync
        )
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    /// An in-memory container for previews and tests.
    @MainActor
    static func inMemory() -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema, configurations: [configuration])
    }
}
