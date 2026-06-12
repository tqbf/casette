import SwiftUI

/// The V1.8 exact/numeric controls at the input pane's trailing edge: the
/// sticky numeric-mode toggle and the session precision menu.
///
/// Why they live HERE and not in a Settings window: both are SESSION-level
/// worker state, not app preferences — precision is the worker `config` op's
/// `precision_digits` (held by the live worker, recorded in the session
/// header, re-applied after restart), and numeric mode scopes the inputs
/// evaluated while it's on. The input pane is where that scope is visible:
/// the toggle reads as pressed exactly while submissions are numeric, right
/// where the user types them.
struct ExactnessControls: View {
    @Bindable var model: ShellModel

    /// The offered precision values. The current session value is always
    /// included (a V1.9-restored session may carry a non-listed precision —
    /// the menu must never show a blank selection).
    private static let standardDigits = [2, 3, 5, 10, 15, 20, 30, 50]

    var body: some View {
        HStack(spacing: Theme.inputElementSpacing) {
            Toggle("≈ Numeric", isOn: $model.numericMode)
                .toggleStyle(.button)
                .help(
                    model.numericMode
                        ? "Numeric mode is on: results you evaluate show as decimals (display only — stored values stay exact). Click to turn off."
                        : "Show results you evaluate as decimals. Display only — stored values stay exact. Stays on until turned off.")
                .accessibilityLabel("Numeric results")
            Picker("Precision", selection: $model.precisionDigits) {
                ForEach(digitChoices, id: \.self) { digits in
                    Text("\(digits) digits").tag(digits)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .help("Decimal digits for ≈ approximations (this session)")
            .accessibilityLabel("Approximation precision")
        }
        .controlSize(.small)
    }

    private var digitChoices: [Int] {
        let current = model.precisionDigits
        return Self.standardDigits.contains(current)
            ? Self.standardDigits
            : (Self.standardDigits + [current]).sorted()
    }
}

#Preview {
    ExactnessControls(model: ShellModel())
        .padding()
}
