//
//  ClassUnchartedApp.swift
//  ClassUncharted
//
//  Created by Bradlee Barnes on 28/10/2024.
//

import SwiftUI

@main
struct ClassUnchartedApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(apiClient: CCAPI(
                clientCredentialProvider: InMemoryClientCredentialProvider(
                    clientCredential: ClientCredential(sessionId: "876815f37fe1fed48e23bb576a4c4884", grantedAt: .now)
                )
            ))
        }
    }
}
