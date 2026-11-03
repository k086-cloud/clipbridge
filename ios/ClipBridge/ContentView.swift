//
//  ContentView.swift
//  ClipBridge
//
//  Created by Charles Chen on 11/1/26.
//

import SwiftUI
import ClipBridgeKit

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
            Text(ClipBridgeIdentifiers.appGroup)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
