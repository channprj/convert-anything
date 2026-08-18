import ConvertAnythingCore
import SwiftUI

public struct SettingsView: View {
  @ObservedObject private var model: AppViewModel
  @State private var draftRules: [ConversionRule] = []

  public init(model: AppViewModel) {
    self.model = model
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("Conversion Rules")
        .font(.title2.weight(.semibold))
      Text("Choose which source extensions map to each local output format.")
        .foregroundStyle(.secondary)

      ScrollView {
        LazyVStack(spacing: 10) {
          ForEach($draftRules) { $rule in
            ruleEditor(rule: $rule)
          }
        }
      }

      if let error = model.settingsError {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }

      HStack {
        Menu("Add Rule") {
          ForEach(MediaFamily.allCases, id: \.self) { family in
            Button(family.rawValue.capitalized) { addRule(family: family) }
          }
        }
        Button("Restore Defaults") {
          Task { await model.restoreDefaultRules() }
        }
        Spacer()
        Button("Save") {
          let proposal = draftRules
          Task { await model.saveRules(proposal) }
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(20)
    .frame(width: 620, height: 480)
    .onAppear {
      draftRules = model.rules
      Task { await model.loadSettings() }
    }
    .onReceive(model.$rules) { draftRules = $0 }
  }

  private func ruleEditor(rule: Binding<ConversionRule>) -> some View {
    let family = rule.wrappedValue.family
    return VStack(alignment: .leading, spacing: 9) {
      HStack {
        Toggle(isOn: rule.isEnabled) {
          Text(family.rawValue.capitalized)
            .font(.headline)
        }
        Spacer()
        Button(role: .destructive) {
          draftRules.removeAll { $0.id == rule.wrappedValue.id }
        } label: {
          Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
      }
      HStack {
        TextField(
          "wav, aiff",
          text: Binding(
            get: { rule.wrappedValue.sourceExtensions.joined(separator: ", ") },
            set: { value in
              rule.wrappedValue.sourceExtensions = value.split(separator: ",").map(String.init)
            }
          )
        )
        .textFieldStyle(.roundedBorder)
        Picker("Target", selection: rule.target) {
          ForEach(RuleCatalog.targets(for: family), id: \.self) { target in
            Text(target.rawValue.uppercased()).tag(target)
          }
        }
        .frame(width: 145)
        Picker("Quality", selection: rule.quality) {
          Text("Smaller").tag(QualityPreset.smaller)
          Text("Balanced").tag(QualityPreset.balanced)
          Text("Higher Quality").tag(QualityPreset.higherQuality)
        }
        .frame(width: 180)
      }
    }
    .padding(12)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
  }

  private func addRule(family: MediaFamily) {
    guard let target = RuleCatalog.targets(for: family).first else { return }
    let suffix = UUID().uuidString.prefix(6).lowercased()
    draftRules.append(
      ConversionRule(
        id: UUID(),
        family: family,
        sourceExtensions: ["new-\(suffix)"],
        target: target,
        quality: .balanced,
        isEnabled: true
      )
    )
  }
}
