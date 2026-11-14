import RadioNoiseKit
import SwiftUI
import UniformTypeIdentifiers

struct NoiseDemoView: View {
  @ObservedObject var model: NoiseDemoModel
  @State private var isImporting = false
  @State private var importsMusic = false
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout =
      horizontalSizeClass == .regular && !dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
      : AnyLayout(VStackLayout(spacing: 16))
    return NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header
          if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red)
              .textSelection(.enabled)
              .accessibilityIdentifier("demo-error")
          }

          layout {
            generatorControls.frame(maxWidth: .infinity)
            referenceControls.frame(maxWidth: .infinity)
          }

          musicControls

          if model.noiseMaterial == .procedural {
            GroupBox {
              VStack(spacing: 14) {
                presetControls
                component(
                  "Шипение", detail: "Широкополосный фон", value: $model.controls.hiss,
                  keyPath: \.hiss)
                component(
                  "Треск", detail: "Короткие нерегулярные импульсы", value: $model.controls.crackle,
                  keyPath: \.crackle)
                component(
                  "Резонанс", detail: "Узкополосный звон и движение тембра",
                  value: $model.controls.resonance, keyPath: \.resonance)
                component(
                  "Дребезг", detail: "Быстрые колебания и прерывистые серии",
                  value: $model.controls.chatter, keyPath: \.chatter)
                component(
                  "Всплески", detail: "Открытие и закрытие шумового порога",
                  value: $model.controls.squelch, keyPath: \.squelch)
              }
              .padding(10)
            } label: {
              Label("Компоненты синтеза", systemImage: "slider.horizontal.3")
            }
          }

          Text(
            "Одинаковые seed и частота дискретизации повторяют последовательность шума. Запись 12 встроена в приложение; выбранные файлы музыки и референсов не копируются. В смеси уровень помехи рассчитывается относительно громкости музыки до приглушения."
          )
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
      }
      .scrollDismissesKeyboard(.interactively)
      .safeAreaInset(edge: .bottom, spacing: 0) {
        transport
          .padding(.horizontal, 20)
          .padding(.vertical, 10)
          .background(.regularMaterial)
      }
      .navigationTitle("Noise Demo")
      .navigationBarTitleDisplayMode(.inline)
      .fileImporter(
        isPresented: $isImporting, allowedContentTypes: importsMusic ? [.audio] : [.wav], allowsMultipleSelection: false
      ) { result in
        switch result {
        case .success(let urls):
          if let url = urls.first {
            if importsMusic { model.importMusic(url) } else { model.importReference(url) }
          }
        case .failure(let error):
          model.errorMessage = "Не удалось выбрать файл: \(error.localizedDescription)"
        }
      }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Радиопомехи · RadioNoiseKit")
          .foregroundStyle(.secondary)
      }
      VStack(alignment: .leading, spacing: 4) {
        Label(
          model.isStarting ? "Подготовка музыки…" : model.isPlaying ? "Воспроизведение · \(model.source.title)" : "Остановлено",
          systemImage: model.isPlaying ? "waveform" : "stop.circle"
        )
        .font(.headline)
        .accessibilityIdentifier("demo-playback-state")
        if let sampleRate = model.sampleRate {
          Text(
            "Аудиотракт: \(sampleRate.formatted(.number.precision(.fractionLength(0)))) Гц · стерео"
          )
          .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
  }

  private var transport: some View {
    VStack(spacing: 12) {
      Picker("Источник", selection: Binding(get: { model.source }, set: { model.selectSource($0) }))
      {
        ForEach(DemoSource.allCases) { source in
          Text(source.title).tag(source)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityLabel("Источник сравнения")
      .accessibilityValue(model.source.title)
      .accessibilityIdentifier("demo-source")
      HStack {
        Spacer()
        Button(action: model.restart) {
          Label("С начала", systemImage: "backward.end")
        }
        .disabled(!model.canStart)
        .help("Запустить выбранный источник с начала с указанным seed")
        Button(action: model.togglePlayback) {
          Label(
            model.isStarting ? "Отмена" : model.isPlaying ? "Стоп" : "Старт",
            systemImage: model.isPlaying ? "stop.fill" : "play.fill"
          )
          .frame(minWidth: 80)
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.space, modifiers: [])
        .disabled(!model.isPlaying && !model.isStarting && !model.canStart)
        .accessibilityIdentifier("demo-transport")
      }
    }
    .controlSize(.large)
  }

  private var presetControls: some View {
    HStack {
      Menu("Пресеты") {
        Button("Смешанный") { model.applyPreset(RadioNoisePresetBlended) }
        Button("07 · Ретрорадио") { model.applyPreset(RadioNoisePresetRetro07) }
        Button("08 · Ретрорадио") { model.applyPreset(RadioNoisePresetRetro08) }
        Button("Резонансный звон") { model.applyPreset(RadioNoisePresetRinging) }
        Button("Затухающие серии") { model.applyPreset(RadioNoisePresetFadingBursts) }
        Button("12 · Радиовсплески (синтез)") { model.applyPreset(RadioNoisePresetUniden12) }
      }
      .help("Меняет характер и компоненты; громкость и seed сохраняются")
      Spacer()
      Button("По умолчанию") { model.resetControls() }
        .help("Восстановить громкость, интенсивность и уровни компонентов; seed не меняется")
    }
    .buttonStyle(.bordered)
    .controlSize(.large)
  }

  private var generatorControls: some View {
    GroupBox("Источник радиопомех") {
      VStack(alignment: .leading, spacing: 14) {
        Picker("Основа шума", selection: Binding(
          get: { model.noiseMaterial }, set: { model.selectNoiseMaterial($0) }
        )) {
          ForEach(DemoNoiseMaterial.allCases) { material in
            Text(material.title).tag(material)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("demo-noise-material")
        if model.noiseMaterial == .recording12 {
          Text("Запись 12 · Uniden radio static bursts, выровненная по громкости. Seed меняет последовательность фрагментов.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        } else {
          Text("Экспериментальный синтез. Пресеты 07 и 08 и компоненты доступны ниже.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        levelControl(
          "Громкость шума соло", value: $model.controls.gainDB, range: -48...0, unit: "дБ",
          decimals: 1)
        if model.noiseMaterial == .procedural {
          levelControl(
            "Характер шума", value: $model.controls.intensity, range: 0...1, unit: "%", scale: 100)
          Text("Характер меняет фактуру синтеза. Глубина поглощения музыки регулируется отдельно ниже.")
            .font(.caption).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Divider()
        HStack {
          Text("Seed")
          TextField("Целое число UInt64", text: $model.seedText)
            .keyboardType(.numberPad)
            .textFieldStyle(.roundedBorder)
            .font(.system(.body, design: .monospaced))
            .accessibilityLabel("Seed радиопомех")
            .accessibilityIdentifier("demo-seed")
          Button(action: model.randomizeSeed) { Image(systemName: "dice") }
            .help("Новый seed; при воспроизведении шума или смеси начать заново")
            .accessibilityLabel("Случайный seed")
        }
        if model.parsedSeed == nil {
          Text("Введите целое число от 0 до 18446744073709551615.")
            .font(.caption).foregroundStyle(.red)
        } else if let seed = model.activeSeed {
          Text("Seed последнего запуска: \(String(seed))")
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        } else {
          Text("Seed применяется при следующем запуске.")
            .font(.caption).foregroundStyle(.secondary)
        }
      }
      .padding(10)
    }
  }

  private var musicControls: some View {
    GroupBox("Музыка с радиопомехами") {
      VStack(alignment: .leading, spacing: 14) {
        Button {
          importsMusic = true
          isImporting = true
        } label: {
          Label("Открыть музыку…", systemImage: "music.note")
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("demo-import-music")
        if let name = model.musicName {
          Text(name).font(.headline).lineLimit(2).textSelection(.enabled)
          Text("\(model.musicDuration.formatted(.number.precision(.fractionLength(1)))) с")
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        } else {
          Text("Выберите WAV, MP3 или другой поддерживаемый аудиофайл, затем источник «Музыка + шум».")
            .foregroundStyle(.secondary)
        }
        HStack {
          Text("Радио эффект")
          Spacer()
          Text("\(Int(model.overlapLevel))").monospacedDigit()
        }
        Slider(value: Binding(get: { model.overlapLevel }, set: { model.setOverlapLevel($0) }),
          in: 0...10, step: 1) {
          Text("Радио эффект")
        }
        .accessibilityValue("\(Int(model.overlapLevel)) из 10")
        .accessibilityIdentifier("demo-overlap")
        HStack {
          Text("Фон радио эффекта")
          Spacer()
          Text("\(Int(model.backgroundLevel))").monospacedDigit()
        }
        Slider(value: Binding(get: { model.backgroundLevel }, set: { model.setBackgroundLevel($0) }),
          in: 0...10, step: 1) {
          Text("Фон радио эффекта")
        }
        .accessibilityValue("\(Int(model.backgroundLevel)) из 10")
        .accessibilityIdentifier("demo-background")
        Text("Чем выше уровень, тем заметнее шум. Фон звучит постоянно, в том числе в тихих местах трека, и не может быть выше эффекта. При одинаковых значениях громкость шума остаётся ровной. Ползунки согласуются автоматически; 0 выключает шум.")
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        levelControl("Громкость смеси", value: $model.monitorGainDB,
          range: -36...0, unit: "дБ", decimals: 1)
        Text("Это отдельная громкость прослушивания. В смеси используется выбранная основа шума: запись 12 или синтез. Громкость шума соло на смесь не влияет.")
          .font(.caption).foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(10)
    }
  }

  private var referenceControls: some View {
    GroupBox("WAV-референс") {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Button {
            importsMusic = false
            isImporting = true
          } label: {
            Label("Открыть WAV…", systemImage: "folder")
          }
          Spacer()
          Toggle("Повтор", isOn: $model.loopsReference)
            .fixedSize()
        }
        if let name = model.referenceName {
          Text(name)
            .font(.headline)
            .lineLimit(2)
            .textSelection(.enabled)
            .help(name)
          Text("\(model.referenceDuration.formatted(.number.precision(.fractionLength(1)))) с")
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        } else {
          Text("Выберите локальный WAV для сравнения.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        levelControl(
          "Громкость референса", value: $model.referenceGainDB, range: -48...0, unit: "дБ",
          decimals: 1)
        Text(
          "Переключение источника во время воспроизведения запускает выбранный звук с начала. Одновременно звучит только один источник."
        )
        .font(.caption).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(10)
    }
  }

  private func component(
    _ title: String, detail: String, value: Binding<Double>,
    keyPath: WritableKeyPath<NoiseControls, Double>
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(detail).font(.caption).foregroundStyle(.secondary)
      }
      HStack(spacing: 12) {
        Slider(value: value, in: 0...1) { Text(title) }
          .accessibilityValue("\(Int((value.wrappedValue * 100).rounded())) процентов")
        Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
          .font(.body.monospacedDigit())
          .frame(width: 48, alignment: .trailing)
        Button("Только") {
          var controls = model.controls
          let selectedLevel = controls[keyPath: keyPath]
          controls.hiss = 0
          controls.crackle = 0
          controls.resonance = 0
          controls.chatter = 0
          controls.squelch = 0
          controls[keyPath: keyPath] = selectedLevel > 0 ? selectedLevel : 1
          model.controls = controls
        }
        .help("Оставить только компонент «\(title)»")
        .accessibilityLabel("Оставить только: \(title)")
        .frame(minHeight: 44)
      }
    }
  }

  private func levelControl(
    _ title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String,
    scale: Double = 1, decimals: Int = 0
  ) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(title)
        Spacer()
        Text(
          "\((value.wrappedValue * scale).formatted(.number.precision(.fractionLength(decimals)))) \(unit)"
        )
        .monospacedDigit()
        .foregroundStyle(.secondary)
      }
      Slider(value: value, in: range) { Text(title) }
        .accessibilityValue(
          "\((value.wrappedValue * scale).formatted(.number.precision(.fractionLength(decimals)))) \(unit)"
        )
    }
  }
}
