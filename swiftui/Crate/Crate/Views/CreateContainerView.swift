import SwiftUI

struct CreateContainerView: View {
    @ObservedObject var viewModel: ContainerListViewModel
    @Binding var isPresented: Bool
    
    @State private var imageName: String = ""
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Launch a new container by providing a Docker image name.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                TextField("Image Name (e.g. nginx, redis)", text: $imageName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                
                Button(action: {
                    guard !imageName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    viewModel.createContainer(image: imageName)
                    isPresented = false
                }) {
                    Text("Run Container")
                        .bold()
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .padding(.horizontal)
                .disabled(imageName.trimmingCharacters(in: .whitespaces).isEmpty)
                
                Spacer()
            }
            .padding(.top, 20)
            .navigationTitle("Create Container")
            #if os(macOS)
            .frame(width: 400, height: 250)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
    }
}
