import SwiftUI
import RealityKit
import RealityKitContent

// Modello prodotto
struct Product: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let imageName: String // nome immagine asset catalog
    let entityName: String // nome risorsa 3D
    let purchaseURL: URL?
}

// Prodotti di esempio aggiornati
let sampleProducts: [Product] = [
    Product(name: "Bamboo", imageName: "bamboo", entityName: "Bamboo", purchaseURL: URL(string: "https://example.com/prodotto1")),
    Product(name: "Perle", imageName: "perla", entityName: "Perle", purchaseURL: URL(string: "https://example.com/prodotto2")),
]

struct ContentView: View {

    /// The environment value to get the instance of the `OpenImmersiveSpaceAction` instance.
    // @Environment(\.openImmersiveSpace) var openImmersiveSpace

    @State private var selectedProduct: Product? = nil
    @State private var loadedEntity: Entity? = nil
    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    @State private var entityPosition: SIMD3<Float> = .zero
    @State private var lastDragTranslation: CGSize = .zero

    @State private var entityScale: Float = 1.0
    @State private var lastMagnification: CGFloat = 1.0
    @State private var entityRotation: Float = 0.0 // in radianti
    @State private var lastRotation: Angle = .radians(0)

    var body: some View {
        VStack {
            // Catalogo prodotti
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 24) {
                    ForEach(sampleProducts) { product in
                        VStack {
                            // Immagine prodotto (placeholder se manca)
                            Image(product.imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 320, height: 320)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(96)
                            Text(product.name)
                                .font(.system(size: 44, weight: .heavy))
                                .foregroundColor(selectedProduct == product ? .white : .primary)
                        }
                        .padding(80)
                        .background(selectedProduct == product ? Color.accentColor : Color.clear)
                        .cornerRadius(96)
                        .overlay(
                            RoundedRectangle(cornerRadius: 96)
                                .stroke(selectedProduct == product ? Color.accentColor : Color.gray.opacity(0.2), lineWidth: 3)
                        )
                        .scaleEffect(selectedProduct == product ? 1.09 : 1.0)
                        .shadow(color: selectedProduct == product ? Color.accentColor.opacity(0.25) : Color.clear, radius: 8, x: 0, y: 2)
                        .onTapGesture {
                            selectedProduct = product
                            loadSelectedEntity()
                        }
                    }
                }
                .padding()
            }
            .glassBackgroundEffect()

            // RealityKit View
            RealityView { content in
                if let entity = loadedEntity {
                    entity.position = entityPosition
                    entity.scale = [entityScale, entityScale, entityScale]
                    entity.transform.rotation = simd_quatf(angle: entityRotation, axis: [0,1,0])
                    content.add(entity)
                }
            } update: { content in
                content.entities.removeAll()
                if let entity = loadedEntity {
                    entity.position = entityPosition
                    entity.scale = [entityScale, entityScale, entityScale]
                    entity.transform.rotation = simd_quatf(angle: entityRotation, axis: [0,1,0])
                    content.add(entity)
                }
            }
            .frame(height: 320)
            .overlay(
                Group {
                    if isLoading {
                        ProgressView("Caricamento…")
                            .padding()
                            .background(.thinMaterial)
                            .cornerRadius(12)
                    } else if selectedProduct == nil {
                        Text("Seleziona un prodotto per visualizzare il modello 3D.")
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            )
            .padding(.vertical)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        // Conversione: 1 punto ≈ 0.002 unità 3D (modificabile per sensibilità)
                        let dx = Float(value.translation.width - lastDragTranslation.width) * 0.002
                        let dy = Float(value.translation.height - lastDragTranslation.height) * -0.002
                        entityPosition.x += dx
                        entityPosition.y += dy
                        lastDragTranslation = value.translation
                    }
                    .onEnded { _ in
                        lastDragTranslation = .zero
                    }
            )
            .simultaneousGesture(
                MagnificationGesture()
                    .onChanged { value in
                        let delta = Float(value / lastMagnification)
                        entityScale *= delta
                        lastMagnification = value
                    }
                    .onEnded { _ in
                        lastMagnification = 1.0
                    }
            )
            .simultaneousGesture(
                RotationGesture()
                    .onChanged { value in
                        let delta = Float(value.radians - lastRotation.radians)
                        entityRotation += delta
                        lastRotation = value
                    }
                    .onEnded { _ in
                        lastRotation = .radians(0)
                    }
            )

            if let product = selectedProduct, let url = product.purchaseURL {
                Link(destination: url) {
                    Label("Acquista ora", systemImage: "cart.fill")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(LinearGradient(colors: [.accentColor, .blue], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(16)
                        .shadow(radius: 6)
                }
                .padding(.bottom)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding([.bottom, .horizontal])
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .onAppear {
            // Carica primo prodotto di default, opzionale:
            // selectedProduct = sampleProducts.first
            // loadSelectedEntity()
        }
    }

    // Carica l'entità 3D per il prodotto selezionato
    func loadSelectedEntity() {
        guard let product = selectedProduct else {
            loadedEntity = nil
            return
        }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let entity = try await Entity(named: product.entityName, in: realityKitContentBundle)
                await MainActor.run {
                    loadedEntity = entity
                    entityPosition = .zero
                    entityScale = 1.0
                    entityRotation = 0.0
                    isLoading = false
                }

                // Open immersive space
                // await openImmersiveSpace(id: "CarView")
            } catch {
                await MainActor.run {
                    loadedEntity = nil
                    isLoading = false
                    errorMessage = "Errore caricamento entità: \(error.localizedDescription)"
                    print("Errore caricamento entità: \(error)")
                }
            }
        }
    }
}

#Preview(windowStyle: .volumetric) {
    ContentView()
}
