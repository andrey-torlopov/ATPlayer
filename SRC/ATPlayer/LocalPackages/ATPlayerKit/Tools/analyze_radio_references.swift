import Foundation
import AVFoundation
import Accelerate
import CryptoKit

// Native, dependency-free measurement of immutable noise references.
// Usage: swiftc -O analyze_radio_references.swift -o /tmp/analyze-radio-references
//        /tmp/analyze-radio-references SOURCE_DIRECTORY OUTPUT_DIRECTORY
struct Quantiles: Codable { let p10: Double; let p50: Double; let p90: Double }
struct Band: Codable {
    let lowHz: Double; let highHz: Double; let meanSquare: Double
    let percentFullSpectrum: Double; let percent100to12000Hz: Double
}
struct Peak: Codable { let frequencyHz: Double; let densityDBFSPerHz: Double; let prominenceDB: Double; let relativeToStrongestDB: Double }
struct Segment: Codable {
    let startSeconds: Double; let endSeconds: Double; let durationSeconds: Double
    let peakEnvelopeDBFS: Double
}
struct Events: Codable {
    let onThresholdDBFS: Double; let offThresholdDBFS: Double
    let minimumDurationSeconds: Double; let mergedGapSeconds: Double
    let segments: [Segment]; let durationSeconds: Quantiles?; let onsetIntervalSeconds: Quantiles?
}
struct CrestCluster: Codable { let startSeconds: Double; let endSeconds: Double; let peakCrestDB: Double }
struct CrestEvents: Codable {
    let thresholdDB: Double; let minimumRMSDBFS: Double; let windowsAboveThreshold: Int
    let clusters: [CrestCluster]; let onsetIntervalSeconds: Quantiles?
}
struct Correlation: Codable { let lagSeconds: Double; let correlation: Double }
struct ModulationBand: Codable { let lowHz: Double; let highHz: Double; let fractionPercent: Double }
struct SpectrumPoint: Codable { let frequencyHz: Double; let powerDensity: Double; let dbfsPerHz: Double }
struct EnvelopePoint: Codable { let timeSeconds: Double; let rmsDBFS: Double; let peakDBFS: Double; let crestDB: Double }
struct Analysis: Codable {
    let file: String; let sha256: String; let sampleRate: Double; let channels: Int; let sourceBitsPerSample: Int; let sampleFrames: Int; let durationSeconds: Double
    let rmsDBFS: Double; let samplePeakDBFS: Double; let crestDB: Double; let dcMeanLeft: Double; let dcMeanRight: Double
    let leftSumSquares: Double; let rightSumSquares: Double; let covarianceSum: Double
    let leftCenteredSumSquares: Double; let rightCenteredSumSquares: Double; let samplePeakLinear: Double
    let crestEvents: CrestEvents
    let stereoCorrelation: Double; let leftRMSDBFS: Double; let rightRMSDBFS: Double; let sideEnergyPercent: Double
    let envelopeRMSDBFS: Quantiles; let windowCrestDB: Quantiles; let envelopeP90MinusP10DB: Double
    let bands: [Band]; let fullSpectrumMeanSquare: Double; let meanSquare100to12000Hz: Double
    let spectralFlatness100to12000: Double; let spectralFlatnessDB: Double; let spectralCentroidHz: Double
    let prominentPSDPeaks: [Peak]
    let burstsAboveMedian6DB: Events; let activityRelativeToP90: Events
    let linearEnvelopeACF: [Correlation]; let logEnvelopeACF: [Correlation]; let significantACFLocalPeaks: [Correlation]
    let modulationBands: [ModulationBand]; let modulationPeaks: [Peak]
    let spectrum: [SpectrumPoint]; let envelope: [EnvelopePoint]; let modulationSpectrum: [SpectrumPoint]
}
struct Report: Encodable {
    let schemaVersion = 1
    let method = "Float32 decode through AVFoundation; stereo energy averaged, 4096-point Hann Welch PSD with 2048 hop; 10-ms RMS envelope (round(sampleRate × 0.01) frames); no loudness normalization"
    let fftFrames = 4096; let hopFrames = 2048; let envelopeSeconds = 0.01
    let psdPeakMethod = "Local maxima 20–12000 Hz; prominence above median of neighbors 3–12 bins away (clipped at spectrum edges); peaks separated by at least 40 Hz; candidates >=6 dB prominence and within 40 dB of strongest PSD bin in the selected band; ordered by prominence, not amplitude; relativeToStrongestDB identifies low-energy lines"
    let flatnessMethod = "geometric mean PSD / arithmetic mean PSD, 100–12000 Hz; near 1 is flatter, near 0 is more concentrated; this is not a perceptual tonality score"
    let acfMethod = "Full centered RMS (linear and dB); overlap-energy normalized lag correlation; local maxima >=0.2, lag >=0.05 s, local prominence >=0.03 above both +-0.05 s endpoints"
    let burstMethod = "Hysteresis median+6/+3 dB or p90-12/-18 dB; merge gaps <=50 ms; retain >=20 ms; thresholds are analytic definitions, not annotated listening events"
    let monoMethod = "Mono is duplicated only inside measurement formulas: channels remains 1, stereo correlation is then not a stereo characteristic, side energy is 0"
    let files: [Analysis]
}
func db(_ amplitude: Double) -> Double { 20 * log10(max(amplitude, 1e-9)) }
func powerDB(_ power: Double) -> Double { 10 * log10(max(power, 1e-18)) }
func percentile(_ sorted: [Double], _ p: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = p * Double(sorted.count - 1), lower = Int(index), upper = min(sorted.count - 1, lower + 1)
    return sorted[lower] + (sorted[upper] - sorted[lower]) * (index - Double(lower))
}
func quantiles(_ values: [Double]) -> Quantiles {
    let sorted = values.sorted()
    return Quantiles(p10: percentile(sorted, 0.1), p50: percentile(sorted, 0.5), p90: percentile(sorted, 0.9))
}
func events(_ envelope: [EnvelopePoint], on: Double, off: Double, duration: Double) -> Events {
    var raw: [(Int, Int)] = [], active: Int?
    for i in envelope.indices {
        if active == nil, envelope[i].rmsDBFS >= on { active = i }
        if let start = active, envelope[i].rmsDBFS < off { raw.append((start, i)); active = nil }
    }
    if let start = active { raw.append((start, envelope.count)) }
    var merged: [(Int, Int)] = []
    for current in raw {
        if let previous = merged.last, current.0 - previous.1 <= 5 {
            merged[merged.count - 1] = (previous.0, current.1)
        } else { merged.append(current) }
    }
    let segments = merged.filter { $0.1 - $0.0 >= 2 }.map { start, end in
        Segment(startSeconds: Double(start) * 0.01, endSeconds: min(duration, Double(end) * 0.01),
                durationSeconds: min(duration, Double(end) * 0.01) - Double(start) * 0.01,
                peakEnvelopeDBFS: envelope[start..<end].map(\.rmsDBFS).max() ?? -180)
    }
    let intervals = zip(segments.dropFirst(), segments).map { $0.startSeconds - $1.startSeconds }
    return Events(onThresholdDBFS: on, offThresholdDBFS: off, minimumDurationSeconds: 0.02,
                  mergedGapSeconds: 0.05, segments: segments,
                  durationSeconds: segments.isEmpty ? nil : quantiles(segments.map(\.durationSeconds)),
                  onsetIntervalSeconds: intervals.isEmpty ? nil : quantiles(intervals))
}
func acf(_ input: [Double]) -> [Correlation] {
    guard input.count > 2 else { return [] }
    let mean = input.reduce(0,+) / Double(input.count)
    let centered = input.map { $0 - mean }
    let maxLag = min(500, input.count / 4)
    return (0...maxLag).map { lag in
        var product = 0.0, leftPower = 0.0, rightPower = 0.0
        for i in 0..<(input.count - lag) {
            let a = centered[i], b = centered[i + lag]
            product += a * b; leftPower += a * a; rightPower += b * b
        }
        return Correlation(lagSeconds: Double(lag) * 0.01,
                           correlation: product / max(1e-30, sqrt(leftPower * rightPower)))
    }
}
func peaks(_ points: [SpectrumPoint], minimumHz: Double, maximumHz: Double, spacing: Double,
           minimumProminence: Double = 6, maximumCount: Int = 12) -> [Peak] {
    var candidates: [Peak] = []
    guard points.count > 28 else { return [] }
    let strongest = points.filter { $0.frequencyHz >= minimumHz && $0.frequencyHz <= maximumHz }.map(\.powerDensity).max() ?? 0
    for i in 1..<(points.count - 1) {
        let p = points[i]
        guard p.frequencyHz >= minimumHz, p.frequencyHz <= maximumHz, p.powerDensity >= strongest * 0.0001,
              p.powerDensity > points[i - 1].powerDensity, p.powerDensity >= points[i + 1].powerDensity else { continue }
        let neighborhood = (max(0,i-12)...min(points.count-1,i+12)).filter { abs($0-i) >= 3 }.map { points[$0].powerDensity }.sorted()
        let prominence = powerDB(p.powerDensity / max(1e-30, percentile(neighborhood, 0.5)))
        if prominence >= minimumProminence {
            candidates.append(Peak(frequencyHz: p.frequencyHz, densityDBFSPerHz: p.dbfsPerHz, prominenceDB: prominence, relativeToStrongestDB: powerDB(p.powerDensity/max(1e-30,strongest))))
        }
    }
    var selected: [Peak] = []
    for p in candidates.sorted(by: { $0.prominenceDB > $1.prominenceDB }) {
        if selected.allSatisfy({ abs($0.frequencyHz - p.frequencyHz) >= spacing }) { selected.append(p) }
        if selected.count >= maximumCount { break }
    }
    return selected
}
func spectrum(_ signal: [Float], sampleRate: Double, frames: Int, hop: Int) throws -> [SpectrumPoint] {
    guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(frames), .FORWARD) else {
        throw NSError(domain: "RadioReferenceFFT", code: 1)
    }
    defer { vDSP_DFT_DestroySetup(setup) }
    var window = [Float](repeating: 0, count: frames)
    vDSP_hann_window(&window, vDSP_Length(min(frames, signal.count)), Int32(vDSP_HANN_NORM))
    let windowEnergy = window.reduce(0.0) { $0 + Double($1 * $1) }
    var real = [Float](repeating: 0, count: frames), imaginary = real, outReal = real, outImaginary = real
    var power = [Double](repeating: 0, count: frames/2+1), count = 0
    for offset in stride(from: 0, through: max(0, signal.count - frames), by: hop) {
        let usable = min(frames, signal.count - offset)
        let mean = signal[offset..<(offset+usable)].reduce(0.0) { $0 + Double($1) } / Double(usable)
        for i in 0..<frames { real[i] = i < usable ? Float(Double(signal[offset+i]) - mean) * window[i] : 0 }
        vDSP_DFT_Execute(setup, real, imaginary, &outReal, &outImaginary)
        for bin in power.indices {
            let r = Double(outReal[bin]), j = Double(outImaginary[bin])
            power[bin] += (r*r+j*j) * (bin == 0 || bin == frames/2 ? 1 : 2) / (sampleRate * windowEnergy)
        }
        count += 1
    }
    return power.indices.map { index in
        let p = power[index] / Double(count)
        return SpectrumPoint(frequencyHz: Double(index) * sampleRate / Double(frames), powerDensity: p, dbfsPerHz: powerDB(p))
    }
}
func analyze(_ url: URL) throws -> Analysis {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard file.length > 0, file.length < Int64(UInt32.max), (1...2).contains(file.processingFormat.channelCount),
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384) else {
        throw NSError(domain: "RadioReferenceFormat", code: 1)
    }
    let channelCount = Int(file.processingFormat.channelCount)
    var left: [Float] = [], right: [Float] = []
    left.reserveCapacity(Int(file.length)); right.reserveCapacity(Int(file.length))
    // A successful AVAudioFile read may be short even before EOF (observed for
    // Float32 mono WAV). Consume every declared PCM frame instead of dropping tails.
    while left.count < Int(file.length) {
        let requested = min(buffer.frameCapacity, AVAudioFrameCount(Int(file.length) - left.count))
        try file.read(into: buffer, frameCount: requested)
        guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
            throw NSError(domain: "RadioReferenceIncompletePCM", code: 1)
        }
        left.append(contentsOf: UnsafeBufferPointer(start: channels[0], count: Int(buffer.frameLength)))
        right.append(contentsOf: UnsafeBufferPointer(start: channels[channelCount == 2 ? 1 : 0], count: Int(buffer.frameLength)))
    }
    let count = left.count, rate = file.processingFormat.sampleRate, duration = Double(count) / rate
    var leftSum = 0.0, rightSum = 0.0, leftSquare = 0.0, rightSquare = 0.0, product = 0.0, samplePeak = 0.0, sideSquare = 0.0
    var envelope: [EnvelopePoint] = []
    let envelopeFrames = Int((rate * 0.01).rounded())
    for start in stride(from: 0, to: count, by: envelopeFrames) {
        let end = min(count, start + envelopeFrames)
        var power = 0.0, peak = 0.0
        for i in start..<end {
            let l = Double(left[i]), r = Double(right[i])
            guard l.isFinite, r.isFinite else { throw NSError(domain: "RadioReferenceNonfinite", code: 1) }
            leftSum += l; rightSum += r; leftSquare += l*l; rightSquare += r*r; product += l*r
            sideSquare += (l-r)*(l-r)*0.25
            power += (l*l+r*r)*0.5; peak = max(peak, abs(l), abs(r))
        }
        let rms = sqrt(power / Double(end-start))
        samplePeak = max(samplePeak, peak)
        envelope.append(EnvelopePoint(timeSeconds: Double(start)/rate, rmsDBFS: db(rms), peakDBFS: db(peak), crestDB: db(peak / max(1e-30,rms))))
    }
    let rms = sqrt((leftSquare + rightSquare) / (2 * Double(count)))
    let covariance = product - leftSum * rightSum / Double(count)
    let correlation = covariance / max(1e-30, sqrt((leftSquare-leftSum*leftSum/Double(count)) * (rightSquare-rightSum*rightSum/Double(count))))
    let lPSD = try spectrum(left, sampleRate: rate, frames: 4096, hop: 2048)
    let rPSD = try spectrum(right, sampleRate: rate, frames: 4096, hop: 2048)
    let psd = zip(lPSD,rPSD).map { a,b in
        let value = (a.powerDensity+b.powerDensity)*0.5
        return SpectrumPoint(frequencyHz:a.frequencyHz,powerDensity:value,dbfsPerHz:powerDB(value))
    }
    let df = rate/4096
    let fullPower = psd.reduce(0.0) { $0+$1.powerDensity*df }
    let analysisBins = psd.filter { $0.frequencyHz >= 100 && $0.frequencyHz < 12000 }
    let analysisPower = analysisBins.reduce(0.0) { $0+$1.powerDensity*df }
    let bands = [(0.0,100.0),(100,300),(300,1000),(1000,3000),(3000,6000),(6000,12000),(12000,rate/2+df)].map { lower,upper in
        let power = psd.filter { $0.frequencyHz >= lower && $0.frequencyHz < upper }.reduce(0.0) { $0+$1.powerDensity*df }
        return Band(lowHz:lower,highHz:min(rate/2,upper),meanSquare:power,
                    percentFullSpectrum:100*power/max(1e-30,fullPower),percent100to12000Hz:100*power/max(1e-30,analysisPower))
    }
    let flatness = exp(analysisBins.reduce(0.0) { $0+log(max(1e-30,$1.powerDensity)) }/Double(analysisBins.count))
        / max(1e-30,analysisPower/(df*Double(analysisBins.count)))
    let centroid = psd.reduce(0.0) { $0+$1.frequencyHz*$1.powerDensity } / max(1e-30,psd.reduce(0.0) { $0+$1.powerDensity })
    let rmsQuantiles = quantiles(envelope.map(\.rmsDBFS)), crestQuantiles = quantiles(envelope.map(\.crestDB))
    let crestThreshold = max(12, crestQuantiles.p90), rmsFloor = max(-90,rmsQuantiles.p10)
    let crestWindows = envelope.indices.filter { envelope[$0].crestDB >= crestThreshold && envelope[$0].rmsDBFS >= rmsFloor }
    var crestRanges: [(Int,Int)] = []
    for index in crestWindows {
        if let last = crestRanges.last, index - last.1 <= 3 { crestRanges[crestRanges.count-1] = (last.0,index) }
        else { crestRanges.append((index,index)) }
    }
    let crestClusters = crestRanges.map { start,end in
        CrestCluster(startSeconds:Double(start)*0.01,endSeconds:min(duration,Double(end+1)*0.01),
                     peakCrestDB:envelope[start...end].map(\.crestDB).max() ?? 0)
    }
    let crestIntervals = zip(crestClusters.dropFirst(),crestClusters).map { $0.startSeconds-$1.startSeconds }
    let crestEventSummary = CrestEvents(thresholdDB:crestThreshold,minimumRMSDBFS:rmsFloor,windowsAboveThreshold:crestWindows.count,
                                       clusters:crestClusters,onsetIntervalSeconds:crestIntervals.isEmpty ? nil : quantiles(crestIntervals))
    let linearEnvelope = envelope.map { pow(10,$0.rmsDBFS/20) }
    let linearACF = acf(linearEnvelope), logACF = acf(envelope.map(\.rmsDBFS))
    var acfPeaks: [Correlation] = []
    if linearACF.count > 12 {
        for i in 5..<(linearACF.count-5) {
            let value = linearACF[i].correlation
            if value >= 0.2, value > linearACF[i-1].correlation, value >= linearACF[i+1].correlation,
               value - max(linearACF[i-5].correlation,linearACF[i+5].correlation) >= 0.03 {
                acfPeaks.append(linearACF[i])
            }
        }
    }
    acfPeaks = Array(acfPeaks.sorted { $0.correlation > $1.correlation }.prefix(10))
    // Mean-centered linear RMS modulation, zero padded; its absolute units are RMS²/Hz.
    // Band fractions and peak frequency are used, not an audio dBFS interpretation.
    var modulationFrames = 1
    while modulationFrames < envelope.count { modulationFrames *= 2 }
    let modPSD = try spectrum(linearEnvelope.map(Float.init), sampleRate: 100, frames: modulationFrames, hop: modulationFrames)
    let modulationPower = modPSD.filter { $0.frequencyHz >= 0.1 }.reduce(0.0) { $0+$1.powerDensity }
    let modulationBands = [(0.1,0.5),(0.5,2.0),(2.0,8.0),(8.0,20.0),(20.0,50.1)].map { low,high in
        let power = modPSD.filter { $0.frequencyHz >= low && $0.frequencyHz < high }.reduce(0.0) { $0+$1.powerDensity }
        return ModulationBand(lowHz:low,highHz:min(high,50),fractionPercent:100*power/max(1e-30,modulationPower))
    }
    return Analysis(file:url.lastPathComponent,sha256:SHA256.hash(data:try Data(contentsOf:url)).map { String(format:"%02x",$0) }.joined(),
                    sampleRate:rate,channels:channelCount,sourceBitsPerSample:(file.fileFormat.settings[AVLinearPCMBitDepthKey] as? Int) ?? 0,sampleFrames:count,durationSeconds:duration,rmsDBFS:db(rms),samplePeakDBFS:db(samplePeak),crestDB:db(samplePeak/max(1e-30,rms)),
                    dcMeanLeft:leftSum/Double(count),dcMeanRight:rightSum/Double(count),
                    leftSumSquares:leftSquare,rightSumSquares:rightSquare,covarianceSum:covariance,
                    leftCenteredSumSquares:leftSquare-leftSum*leftSum/Double(count),
                    rightCenteredSumSquares:rightSquare-rightSum*rightSum/Double(count),samplePeakLinear:samplePeak,
                    crestEvents:crestEventSummary,stereoCorrelation:correlation,
                    leftRMSDBFS:db(sqrt(leftSquare/Double(count))),rightRMSDBFS:db(sqrt(rightSquare/Double(count))),
                    sideEnergyPercent:100*sideSquare/max(1e-30,(leftSquare+rightSquare)*0.5),
                    envelopeRMSDBFS:rmsQuantiles,windowCrestDB:crestQuantiles,envelopeP90MinusP10DB:rmsQuantiles.p90-rmsQuantiles.p10,
                    bands:bands,fullSpectrumMeanSquare:fullPower,meanSquare100to12000Hz:analysisPower,
                    spectralFlatness100to12000:flatness,spectralFlatnessDB:powerDB(flatness),spectralCentroidHz:centroid,
                    prominentPSDPeaks:peaks(psd,minimumHz:20,maximumHz:12000,spacing:40),
                    burstsAboveMedian6DB:events(envelope,on:rmsQuantiles.p50+6,off:rmsQuantiles.p50+3,duration:duration),
                    activityRelativeToP90:events(envelope,on:rmsQuantiles.p90-12,off:rmsQuantiles.p90-18,duration:duration),
                    linearEnvelopeACF:linearACF,logEnvelopeACF:logACF,significantACFLocalPeaks:acfPeaks,
                    modulationBands:modulationBands,modulationPeaks:peaks(modPSD,minimumHz:0.1,maximumHz:50,spacing:0.2,minimumProminence:3,maximumCount:8),
                    spectrum:psd,envelope:envelope,modulationSpectrum:modPSD)
}
func xml(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
}
func writePlots(_ a: Analysis, directory: URL) throws {
    let height = 1060.0, left = 90.0, right = 1450.0
    var svg = ["<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1500\" height=\"1060\" viewBox=\"0 0 1500 1060\"><rect width=\"1500\" height=\"1060\" fill=\"white\"/><g font-family=\"Helvetica,Arial,sans-serif\" font-size=\"14\" fill=\"#17202a\">"]
    func text(_ x: Double,_ y: Double,_ label: String,_ size: Int = 14) {
        svg.append("<text x=\"\(x)\" y=\"\(y)\" font-size=\"\(size)\">\(xml(label))</text>")
    }
    text(left,30,a.file,22)
    text(left,54,String(format:"RMS %.2f dBFS | crest %.2f dB | L/R correlation %.5f | measured PCM, no listening judgment",a.rmsDBFS,a.crestDB,a.stereoCorrelation))
    func panel(y: Double,h: Double,title: String,xTicks: [(Double,String)],yTicks: [(Double,String)],
               xMap: (Double)->Double,yMap: (Double)->Double) {
        text(left,y-16,title,17)
        svg.append("<rect x=\"\(left)\" y=\"\(y)\" width=\"\(right-left)\" height=\"\(h)\" fill=\"#f9fafb\" stroke=\"#d7dbdf\"/>")
        for (value,label) in xTicks {
            let x=xMap(value)
            svg.append("<line x1=\"\(x)\" x2=\"\(x)\" y1=\"\(y)\" y2=\"\(y+h)\" stroke=\"#e2e5e8\"/>")
            text(x-14,y+h+20,label)
        }
        for (value,label) in yTicks {
            let yy=yMap(value)
            svg.append("<line x1=\"\(left)\" x2=\"\(right)\" y1=\"\(yy)\" y2=\"\(yy)\" stroke=\"#e2e5e8\"/>")
            text(left-58,yy+4,label)
        }
    }
    func line(_ points: [(Double,Double)],color:String,xMap:(Double)->Double,yMap:(Double)->Double) {
        let path=points.map { String(format:"%.2f,%.2f",xMap($0.0),yMap($0.1)) }.joined(separator:" ")
        svg.append("<polyline fill=\"none\" stroke=\"\(color)\" stroke-width=\"1.2\" points=\"\(path)\"/>")
    }
    let frequencyX: (Double)->Double = { left+(log10(max(20,$0))-log10(20))/(log10(24000)-log10(20))*(right-left) }
    let psdY: (Double)->Double = { 90+(1-(max(-125,min(-25,$0))+125)/100)*190 }
    panel(y:90,h:190,title:"Welch PSD — dBFS/Hz; Hann 4096 / hop 2048; shared axis across files",
          xTicks:[(20,"20 Hz"),(100,"100"),(300,"300"),(1000,"1k"),(3000,"3k"),(6000,"6k"),(12000,"12k"),(24000,"24k")],
          yTicks:[(-120,"-120"),(-100,"-100"),(-80,"-80"),(-60,"-60"),(-40,"-40")],xMap:frequencyX,yMap:psdY)
    line(a.spectrum.filter { $0.frequencyHz>=20 }.map { ($0.frequencyHz,$0.dbfsPerHz) },color:"#005f99",xMap:frequencyX,yMap:psdY)
    let timeX:(Double)->Double = { left+$0/a.durationSeconds*(right-left) }
    let envelopeY:(Double)->Double = { 355+(1-(max(-90,min(0,$0))+90)/90)*180 }
    panel(y:355,h:180,title:"10-ms RMS (blue) and sample peak (orange), dBFS — original levels retained",
          xTicks:(0...8).map { (a.durationSeconds*Double($0)/8,String(format:"%.1f s",a.durationSeconds*Double($0)/8)) },
          yTicks:[(-90,"-90"),(-60,"-60"),(-30,"-30"),(0,"0")],xMap:timeX,yMap:envelopeY)
    line(a.envelope.map { ($0.timeSeconds,$0.peakDBFS) },color:"#d8791a",xMap:timeX,yMap:envelopeY)
    line(a.envelope.map { ($0.timeSeconds,$0.rmsDBFS) },color:"#005f99",xMap:timeX,yMap:envelopeY)
    let maximumLag = a.linearEnvelopeACF.last?.lagSeconds ?? 5
    let lagX:(Double)->Double = { left+$0/maximumLag*(right-left) }
    let acfY:(Double)->Double = { 610+(1-max(-1,min(1,$0)))*80 }
    panel(y:610,h:160,title:"Envelope autocorrelation — linear RMS (blue), log RMS (gray); trends can create correlation",
          xTicks:(0...5).map { (maximumLag*Double($0)/5,String(format:"%.2f s",maximumLag*Double($0)/5)) },
          yTicks:[(-1,"-1"),(0,"0"),(0.5,"0.5"),(1,"1")],xMap:lagX,yMap:acfY)
    line(a.logEnvelopeACF.map { ($0.lagSeconds,$0.correlation) },color:"#939aa2",xMap:lagX,yMap:acfY)
    line(a.linearEnvelopeACF.map { ($0.lagSeconds,$0.correlation) },color:"#005f99",xMap:lagX,yMap:acfY)
    let modulation=a.modulationSpectrum.filter { $0.frequencyHz>=0.1 }
    let maxMod=modulation.map(\.powerDensity).max() ?? 1
    let modulationX:(Double)->Double = { left+(log10(max(0.1,$0))+1)/(log10(50)+1)*(right-left) }
    let modulationY:(Double)->Double = { 845+(1-(max(-60,min(0,$0))+60)/60)*150 }
    panel(y:845,h:150,title:"Linear RMS modulation spectrum — dB relative to strongest modulation bin (not audio dBFS)",
          xTicks:[(0.1,"0.1 Hz"),(0.5,"0.5"),(2,"2"),(8,"8"),(20,"20"),(50,"50")],
          yTicks:[(-60,"-60"),(-40,"-40"),(-20,"-20"),(0,"0")],xMap:modulationX,yMap:modulationY)
    line(modulation.map { ($0.frequencyHz,powerDB($0.powerDensity/max(1e-30,maxMod))) },color:"#42712f",xMap:modulationX,yMap:modulationY)
    text(left,height-16,"SHA256: \(a.sha256)",11)
    svg.append("</g></svg>")
    let stem=URL(fileURLWithPath:a.file).deletingPathExtension().lastPathComponent
    try svg.joined(separator:"\n").write(to:directory.appendingPathComponent(stem+"-measurements.svg"),atomically:false,encoding:.utf8)
    let spectrumCSV="frequency_hz,power_density,dbfs_per_hz\n"+a.spectrum.map { "\($0.frequencyHz),\($0.powerDensity),\($0.dbfsPerHz)" }.joined(separator:"\n")+"\n"
    try spectrumCSV.write(to:directory.appendingPathComponent(stem+"-psd.csv"),atomically:false,encoding:.utf8)
    let envelopeCSV="seconds,rms_dbfs,sample_peak_dbfs,crest_db\n"+a.envelope.map { "\($0.timeSeconds),\($0.rmsDBFS),\($0.peakDBFS),\($0.crestDB)" }.joined(separator:"\n")+"\n"
    try envelopeCSV.write(to:directory.appendingPathComponent(stem+"-envelope.csv"),atomically:false,encoding:.utf8)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let allWAV = arguments.contains("--all-wav")
    let positional = arguments.filter { $0 != "--all-wav" }
    guard positional.count == 2, !positional.contains(where: { $0.hasPrefix("--") }) else {
        throw NSError(domain:"Usage: analyzer SOURCE_DIRECTORY OUTPUT_DIRECTORY [--all-wav]",code:1)
    }
    let source = URL(fileURLWithPath:positional[0],isDirectory:true)
    let output = URL(fileURLWithPath:positional[1],isDirectory:true)
    try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
    let allowed = Set(["07","08","09","10","11","12"])
    let urls = try FileManager.default.contentsOfDirectory(at:source,includingPropertiesForKeys:nil)
        .filter { $0.pathExtension.lowercased()=="wav" && (allWAV || allowed.contains(String($0.lastPathComponent.prefix(2)))) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !urls.isEmpty, allWAV || urls.count == 6 else { throw NSError(domain:"Expected exactly six reference WAV files 07–12, or use --all-wav for a nonempty directory",code:1) }
    var analyses: [Analysis] = []
    for url in urls {
        let result = try analyze(url); analyses.append(result)
        try writePlots(result, directory:output)
        print(String(format:"%@ duration=%.3fs RMS=%.2fdBFS crest=%.2fdB corr=%.5f envelopeP10/P50/P90=%.2f/%.2f/%.2fdBFS flatness=%.4f centroid=%.0fHz bursts=%d",
                     result.file,result.durationSeconds,result.rmsDBFS,result.crestDB,result.stereoCorrelation,
                     result.envelopeRMSDBFS.p10,result.envelopeRMSDBFS.p50,result.envelopeRMSDBFS.p90,
                     result.spectralFlatness100to12000,result.spectralCentroidHz,result.burstsAboveMedian6DB.segments.count))
    }
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
    try encoder.encode(Report(files:analyses)).write(to:output.appendingPathComponent("reference-analysis.json"))
} catch {
    FileHandle.standardError.write(Data("Reference analysis failed: \(error)\n".utf8)); exit(1)
}
