import SwiftUI

struct SessionView: View {
    @StateObject private var viewModel: ViewModel
    @Environment(\.dismiss) var dismiss

    // `pending` non-nil => this session came from an answered incoming call: inject its
    // token/name and join immediately (no JWT prompt). nil => normal in-app join flow.
    init(pending: CallManager.PendingSession? = nil) {
        let vm = ViewModel()
        if let p = pending {
            vm.jwtToken = p.token
            vm.sessionName = p.sessionName
            vm.userName = p.userName
            vm.callUUID = p.id
            vm.autoJoin = true
            vm.inJWTInput = false
        }
        _viewModel = StateObject(wrappedValue: vm)
    }

    var body: some View {
        if viewModel.inSession {
            NavigationStack {
                ScrollView {
                    VStack {
                        VStack {
                            if viewModel.videoOn {
                                LocalVideoView(viewModel: viewModel)
                            } else {
                                PlaceholderView(name: viewModel.userName)
                            }
                        }
                        .aspectRatio(1, contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .padding()
                        ForEach(viewModel.remoteUsers.indices, id: \.self) { index in
                            VStack {
                                if viewModel.remoteUsers[index].getVideoCanvas()?.videoStatus()?.on ?? false {
                                    RemoteVideoView(viewModel: viewModel, index: index)
                                } else {
                                    PlaceholderView(name: viewModel.remoteUsers[index].getName() ?? "")
                                }
                            }
                            .aspectRatio(1, contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                    }
                }
            }
            .toolbar {
                if viewModel.inSession {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button(action: {
                            viewModel.toggleVideo()
                        }, label: {
                            Label {
                                Text(viewModel.videoOn ? "Stop Video" : "Start Video").fixedSize()
                            } icon: {
                                Image(systemName: viewModel.videoOn ? "video.slash" : "video")
                                    .frame(width: 24, height: 24)
                            }
                        })
                        .buttonStyle(.borderless)
                        Spacer()
                        Button(action: {
                            viewModel.toggleAudio()
                        }, label: {
                            Label {
                                Text(viewModel.audioOn ? "Mute" : "Unmute").fixedSize()
                            } icon: {
                                Image(systemName: viewModel.audioOn ? "mic.slash" : "mic")
                                    .frame(width: 24, height: 24)
                            }
                        })
                        .buttonStyle(.borderless)
                        Spacer()
                        Button(action: {
                            viewModel.leaveSession()
                            dismiss()
                        }, label: {
                            Label {
                                Text("End Session").fixedSize()
                            } icon: {
                                Image(systemName: "phone.down")
                                    .frame(width: 24, height: 24)
                            }
                        })
                        .buttonStyle(.borderless)
                    }
                }
            }
            .labelStyle(VerticalLabelStyle())
            .toolbarRole(.editor)
            .navigationBarBackButtonHidden(true)
        } else {
            NavigationStack {
                Text("Loading session...")
                    .font(.title)
                    .navigationBarBackButtonHidden(true)
                    .alert("JWT Token Required", isPresented: $viewModel.inJWTInput) {
                        TextField("Enter your JWT Token", text: $viewModel.userInputJWT)
                            .disableAutocorrection(true)
                        Button("Join") {
                            viewModel.shouldJoin = true
                        }
                        Button("Cancel", role: .cancel) {
                            dismiss()
                        }
                    } message: {
                        Text("You can choose to copy and paste your generated JWT Token here OR leave it as empty if you have added it in the SessionView+Extension jwtToken variable")
                    }
                    .onAppear {
                        if viewModel.autoJoin { viewModel.shouldJoin = true }
                    }
                    .task(id: viewModel.shouldJoin) {
                        guard viewModel.shouldJoin else { return }
                        await viewModel.joinSession()
                        viewModel.shouldJoin = false
                    }.alert("Error", isPresented: $viewModel.joinSessionFailed, actions: {
                        Button(action: {
                            dismiss()
                        }) { Text("OK") }
                    }, message: {
                        Text("\(viewModel.errorMessage)")
                    })
            }
        }
    }
    
}

#Preview {
    SessionView()
}

public struct VerticalLabelStyle: LabelStyle {
    public func makeBody(configuration: Configuration) -> some View {
        VStack {
            configuration.icon.font(.headline)
            configuration.title.font(.footnote)
        }
    }
}

public struct PlaceholderView: View {
    @State var name: String

    public var body: some View {
        VStack {
            Image(systemName: "person.fill")
                .foregroundStyle(.white)
            Text(name)
                .foregroundStyle(.white)
        }
        .frame(maxHeight: .infinity)
    }
}

public struct LocalVideoView: UIViewRepresentable {
    @State var viewModel: SessionView.ViewModel

    public func makeUIView(context _: Context) -> UIView {
        let videoView = UIView()
        viewModel.attachLocalVideo(to: videoView)
        return videoView
    }

    public func updateUIView(_ uiView: UIView, context _: Context) {
        viewModel.updateLocalVideo(to: uiView)
    }
}

public struct RemoteVideoView: UIViewRepresentable {
    @State var viewModel: SessionView.ViewModel
    @State var index: Int

    public func makeUIView(context _: Context) -> UIView {
        let videoView = UIView()
        return videoView
    }

    public func updateUIView(_ uiView: UIView, context _: Context) {
        viewModel.updateRemoteVideo(to: uiView, index: index)
    }
}
