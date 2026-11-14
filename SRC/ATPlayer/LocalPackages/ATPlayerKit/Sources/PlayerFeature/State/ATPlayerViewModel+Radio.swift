import PlaybackDomain

extension ATPlayerViewModel {
    func setRadioEffectIntensity(_ value: Int) {
        let level = max(0, min(10, value))
        // Lowering the maximum lowers its floor; raising it preserves the
        // chosen floor, including an explicit zero background.
        let background = min(level, radioSettings.backgroundIntensity)
        updateRadioSettings(RadioSettings(effectIntensity: level, backgroundIntensity: background))
    }

    func setRadioBackgroundIntensity(_ value: Int) {
        // The settings invariant raises the maximum when the floor overtakes it.
        updateRadioSettings(RadioSettings(effectIntensity: radioSettings.effectIntensity,
                                          backgroundIntensity: value))
    }

    private func updateRadioSettings(_ settings: RadioSettings) {
        guard radioSettings != settings else { return }
        radioSettings = settings
        radioPreferences.save(settings)
        playbackService.applyRadioSettings(settings)
    }
}
