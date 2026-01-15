import UIKit
import ReaderCore

public final class ReaderSettingsViewController: UITableViewController {
    private var fontScale: CGFloat
    private let onFontScaleChanged: (CGFloat) -> Void
    private let fontManager = FontScaleManager.shared

    // Discrete font scale steps
    private let fontScaleSteps: [CGFloat] = [1.25, 1.5, 1.75, 2.0]

    private var apiKey: String = UserDefaults.standard.string(forKey: "OpenRouterAPIKey") ?? ""
    private var selectedModel: String = UserDefaults.standard.string(forKey: "OpenRouterModel") ?? "google/gemini-2.0-flash-exp:free"

    private let models = [
        ("google/gemini-2.0-flash-exp:free", "Gemini 2.0 Flash (Free, Default)"),
        ("x-ai/grok-4.1-fast", "xAI: Grok 4.1 Fast"),
        ("google/gemini-2.5-flash-lite", "Google: Gemini 2.5 Flash Lite"),
        ("anthropic/claude-3-haiku", "Anthropic: Claude 3 Haiku"),
        ("openai/gpt-4.1-nano", "OpenAI: GPT-4.1 Nano")
    ]

    public init(fontScale: CGFloat, onFontScaleChanged: @escaping (CGFloat) -> Void) {
        self.fontScale = fontScale
        self.onFontScaleChanged = onFontScaleChanged
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        title = "Settings"
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismiss(_:)))

        // Observe font scale changes to update UI
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(fontScaleDidChange),
            name: FontScaleManager.fontScaleDidChangeNotification,
            object: nil
        )
    }

    @objc private func fontScaleDidChange() {
        tableView.reloadData()
    }

    @objc private func dismiss(_ sender: Any) {
        dismiss(animated: true)
    }

    // MARK: - Table View

    public override func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    public override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1 // Font size
        case 1: return 2 // API key + link
        case 2: return 1 // Model picker
        default: return 0
        }
    }

    public override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Font Size"
        case 1: return "OpenRouter API"
        case 2: return "AI Model"
        default: return nil
        }
    }

    public override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 1 {
            return "Your API key is stored securely on device and only used to call the LLM when you select text."
        }
        return nil
    }

    public override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.section {
        case 0:
            return fontSizeCell()
        case 1:
            if indexPath.row == 0 {
                return apiKeyCell()
            } else {
                return linkCell()
            }
        case 2:
            return modelPickerCell()
        default:
            return UITableViewCell()
        }
    }

    public override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        if indexPath.section == 1 && indexPath.row == 1 {
            // Open OpenRouter link
            if let url = URL(string: "https://openrouter.ai/keys") {
                UIApplication.shared.open(url)
            }
        } else if indexPath.section == 2 {
            showModelPicker()
        }
    }

    // MARK: - Cells

    private func fontSizeCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none

        let slider = UISlider()
        slider.minimumValue = Float(fontScaleSteps.first ?? 1.25)
        slider.maximumValue = Float(fontScaleSteps.last ?? 2.0)
        slider.value = Float(fontScale)
        slider.translatesAutoresizingMaskIntoConstraints = false
        // Update label only during drag (no heavy computation)
        slider.addTarget(self, action: #selector(fontSizeSliding(_:)), for: .valueChanged)
        // Apply changes only on release
        slider.addTarget(self, action: #selector(fontSizeReleased(_:)), for: [.touchUpInside, .touchUpOutside])

        let minLabel = UILabel()
        minLabel.text = "A"
        minLabel.font = fontManager.scaledFont(size: 12)
        minLabel.translatesAutoresizingMaskIntoConstraints = false

        let maxLabel = UILabel()
        maxLabel.text = "A"
        maxLabel.font = fontManager.scaledFont(size: 20)
        maxLabel.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.text = String(format: "%.2gx", fontScale)
        valueLabel.font = fontManager.scaledFont(size: 14)
        valueLabel.textColor = .secondaryLabel
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.tag = 100

        let stack = UIStackView(arrangedSubviews: [minLabel, slider, maxLabel])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        cell.contentView.addSubview(stack)
        cell.contentView.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),

            valueLabel.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),
            valueLabel.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            valueLabel.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
        ])

        return cell
    }

    private func apiKeyCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.selectionStyle = .none

        let textField = UITextField()
        textField.placeholder = "API Key"
        textField.text = apiKey
        textField.isSecureTextEntry = true
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.font = fontManager.bodyFont
        textField.translatesAutoresizingMaskIntoConstraints = false
        textField.addTarget(self, action: #selector(apiKeyChanged(_:)), for: .editingChanged)

        cell.contentView.addSubview(textField)

        NSLayoutConstraint.activate([
            textField.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 12),
            textField.leadingAnchor.constraint(equalTo: cell.contentView.leadingAnchor, constant: 16),
            textField.trailingAnchor.constraint(equalTo: cell.contentView.trailingAnchor, constant: -16),
            textField.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -12)
        ])

        return cell
    }

    private func linkCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.textLabel?.text = "Get API Key from OpenRouter"
        cell.textLabel?.textColor = .systemBlue
        cell.textLabel?.font = fontManager.scaledFont(size: 14)
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    private func modelPickerCell() -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.textLabel?.text = "Model"
        cell.textLabel?.font = fontManager.bodyFont
        cell.detailTextLabel?.text = models.first(where: { $0.0 == selectedModel })?.1 ?? selectedModel
        cell.detailTextLabel?.font = fontManager.bodyFont
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    // MARK: - Actions

    /// Snaps a value to the nearest discrete font scale step
    private func snapToStep(_ value: CGFloat) -> CGFloat {
        var closest = fontScaleSteps[0]
        var minDist = abs(value - closest)
        for step in fontScaleSteps {
            let dist = abs(value - step)
            if dist < minDist {
                minDist = dist
                closest = step
            }
        }
        return closest
    }

    /// Called during slider drag - only updates the label, no heavy computation
    @objc private func fontSizeSliding(_ slider: UISlider) {
        let snappedValue = snapToStep(CGFloat(slider.value))

        // Update label to show snapped value
        if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)),
           let label = cell.contentView.viewWithTag(100) as? UILabel {
            label.text = String(format: "%.2gx", snappedValue)
        }
    }

    /// Called when slider is released - applies the font scale change
    @objc private func fontSizeReleased(_ slider: UISlider) {
        let snappedValue = snapToStep(CGFloat(slider.value))

        // Snap slider to the discrete value
        slider.value = Float(snappedValue)

        // Only trigger expensive updates if value actually changed
        guard snappedValue != fontScale else { return }

        fontScale = snappedValue
        fontManager.fontScale = fontScale  // Persist to UserDefaults
        onFontScaleChanged(fontScale)

        // Update label
        if let cell = tableView.cellForRow(at: IndexPath(row: 0, section: 0)),
           let label = cell.contentView.viewWithTag(100) as? UILabel {
            label.text = String(format: "%.2gx", fontScale)
        }
    }

    @objc private func apiKeyChanged(_ textField: UITextField) {
        apiKey = textField.text ?? ""
        UserDefaults.standard.set(apiKey, forKey: "OpenRouterAPIKey")
    }

    private func showModelPicker() {
        let alert = UIAlertController(title: "Select Model", message: nil, preferredStyle: .actionSheet)

        for (modelId, modelName) in models {
            let action = UIAlertAction(title: modelName, style: .default) { [weak self] _ in
                self?.selectedModel = modelId
                UserDefaults.standard.set(modelId, forKey: "OpenRouterModel")
                self?.tableView.reloadRows(at: [IndexPath(row: 0, section: 2)], with: .automatic)
            }
            if modelId == selectedModel {
                action.setValue(true, forKey: "checked")
            }
            alert.addAction(action)
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        if let popover = alert.popoverPresentationController {
            popover.sourceView = tableView
            popover.sourceRect = tableView.rectForRow(at: IndexPath(row: 0, section: 2))
        }

        present(alert, animated: true)
    }
}
