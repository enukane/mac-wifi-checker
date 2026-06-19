import SwiftUI

struct ContentView: View {
    @Environment(AppViewModel.self) private var vm
    var body: some View {
        Text("Mac Wi-Fi Checker")
    }
}
