import SwiftUI

struct StartView: View {
    var body: some View {
        NavigationStack {
            VStack {
                NavigationLink(destination: SessionView()) {
                    Text("Join Session")
                        .foregroundStyle(Color.blue)
                        .padding()
                        .background(Color.white.clipShape(.rect(cornerRadius: 8)))
                }
            }
            .padding()
        }
    }
}

#Preview {
    StartView()
}
