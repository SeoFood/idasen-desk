import IdasenDeskCore
import SwiftUI

struct DesksSettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Active desk", selection: activeDeskBinding) {
                Text("None").tag(Optional<DeskID>.none)
                ForEach(model.settings.savedDesks) { desk in
                    Text(desk.displayName).tag(Optional(desk.id))
                }
            }

            Table(model.settings.savedDesks) {
                TableColumn("Name") { desk in
                    TextField("Name", text: nameBinding(for: desk))
                        .textFieldStyle(.roundedBorder)
                }
                TableColumn("Sit") { desk in
                    presetField(for: desk, kind: .sit)
                }
                TableColumn("Stand") { desk in
                    presetField(for: desk, kind: .stand)
                }
                TableColumn("") { desk in
                    Button {
                        model.forgetDesk(desk.id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Forget")
                }
                .width(42)
            }
            .frame(minHeight: 250)

            HStack {
                Button {
                    model.scan()
                } label: {
                    Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                }
                Button {
                    OnboardingWindowPresenter.shared.present()
                } label: {
                    Label("Pair", systemImage: "plus")
                }
            }
        }
    }

    private var activeDeskBinding: Binding<DeskID?> {
        Binding {
            model.settings.activeDeskID
        } set: { id in
            if let id {
                model.connect(to: id)
            }
        }
    }

    private func nameBinding(for desk: SavedDesk) -> Binding<String> {
        Binding {
            model.settings.savedDesks.first(where: { $0.id == desk.id })?.displayName ?? desk.displayName
        } set: { value in
            model.renameDesk(desk.id, name: value)
        }
    }

    private func presetField(for desk: SavedDesk, kind: DeskPresetKind) -> some View {
        TextField(kind.rawValue.capitalized, value: presetBinding(for: desk, kind: kind), format: .number.precision(.fractionLength(0...1)))
            .textFieldStyle(.roundedBorder)
            .frame(width: 72)
    }

    private func presetBinding(for desk: SavedDesk, kind: DeskPresetKind) -> Binding<Double> {
        Binding {
            let height = model.settings.savedDesks
                .first(where: { $0.id == desk.id })?
                .presetHeight(for: kind) ?? DeskHeight(centimeters: kind == .sit ? 70 : 110)
            return UnitConversion.displayValue(for: height, system: model.settings.measurementSystem)
        } set: { value in
            let height = UnitConversion.height(fromDisplayValue: value, system: model.settings.measurementSystem)
            model.setPreset(kind, height: height, for: desk.id)
        }
    }
}

