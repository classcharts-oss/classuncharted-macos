//
//  ContentView.swift
//  ClassUncharted
//
//  Created by Bradlee Barnes on 28/10/2024.
//

import SwiftUI

struct ContentView<A: APIProvider>: View {
    @StateObject var apiClient: A
    @State var announcements: [Announcement] = []

    init(apiClient: A) {
        self._apiClient = StateObject(wrappedValue: apiClient)
    }

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            ForEach(announcements, id: \.id) {
                Text("Hello, world! \($0.title)")
            }
        }
        .padding()
        .task {
            do {
                let announcements = try await apiClient.getAnnouncements()
                self.announcements = announcements.data
            } catch let error {
                print(error)
            }
        }
    }
}

#Preview {
    ContentView(
        apiClient: CCAPI(
            clientCredentialProvider: InMemoryClientCredentialProvider(
                clientCredential: ClientCredential(sessionId: "876815f37fe1fed48e23bb576a4c4884", grantedAt: .now)
            )
        )
    )
}
