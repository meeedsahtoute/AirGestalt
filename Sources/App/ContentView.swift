//
//  ContentView.swift
//  AirGestalt
//
//  Flagship Root View with 4 Core Navigation Tabs & Continuity Pairing Modal Overlay.
//

import SwiftUI

public struct ContentView: View {
    @ObservedObject var continuityDecoder = ContinuityDecoder.shared
    @State private var selectedTab: Int = 0

    public init() {}

    public var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tabItem {
                        Label("Dashboard", systemImage: "airpodspro")
                    }
                    .tag(0)

                MicStudioView()
                    .tabItem {
                        Label("Mic Studio", systemImage: "mic.badge.plus")
                    }
                    .tag(1)

                EQAndToolsView()
                    .tabItem {
                        Label("EQ & Tools", systemImage: "slider.vertical.3")
                    }
                    .tag(2)

                GATTExplorerView()
                    .tabItem {
                        Label("GATT Lab", systemImage: "cpu")
                    }
                    .tag(3)
            }
            .tint(.blue)

            // Apple Proximity Pairing Bottom-Sheet Modal
            if continuityDecoder.shouldShowPairingPopup {
                PairingPopupView(
                    continuityDecoder: continuityDecoder,
                    isPresented: $continuityDecoder.shouldShowPairingPopup
                )
                .transition(.opacity)
                .zIndex(99)
            }
        }
        .onAppear {
            continuityDecoder.startScanning()
            do {
                try SharedAudioEngine.shared.startEngine()
            } catch {
                print("Audio Engine startup error: \(error)")
            }
        }
    }
}
