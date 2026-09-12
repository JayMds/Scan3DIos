import SwiftUI

/// Point d'entrée de l'app — l'équivalent du `App.tsx` racine d'un projet Expo.
@main
struct Scan3DApp: App {
    var body: some Scene {
        WindowGroup {
            AccueilView()
        }
    }
}
