import SwiftUI

struct ContentView: View {
    var body: some View {
        ZStack {
            Color.brandForestGreen
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Naked Pantree")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.brandWarmCream)
                Text("Pants optional inventory.")
                    .font(.headline)
                    .foregroundStyle(.brandWarmCream.opacity(0.85))
            }
            .multilineTextAlignment(.center)
            .padding()
        }
    }
}

#Preview {
    ContentView()
}
