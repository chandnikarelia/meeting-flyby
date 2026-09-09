import AVFoundation

/// Plays real recorded animal sound clips bundled in the app (Contents/Resources),
/// sourced from Mixkit's free sound effects (no attribution required).
enum AnimalSound {
    private static var player: AVAudioPlayer?

    private static let files: [String: String] = [
        "🐶": "dog",
        "🐱": "cat",
        "🐷": "pig",
        "🐰": "bunny" // real bunnies don't vocalize much — using a mouse squeak as the closest cute stand-in
    ]

    static func play(for character: String) {
        guard let name = files[character],
              let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return }
        do {
            let newPlayer = try AVAudioPlayer(contentsOf: url)
            player = newPlayer
            newPlayer.volume = 0.9
            newPlayer.play()
        } catch {
            // No sound is better than crashing the flyby over a missing/corrupt clip.
        }
    }
}
