import Testing
@testable import Scan3DCore

@Suite("Avancement de la reconstruction")
struct ReconstructionProgressTests {

    @Test("Le pourcentage est arrondi et borné", arguments: [
        (0.0, 0), (0.424, 42), (0.425, 43), (1.0, 100), (1.2, 100), (-0.5, 0),
        (Double.nan, 0), (Double.infinity, 0),
    ])
    func pourcentage(fraction: Double, attendu: Int) {
        #expect(ReconstructionProgress.percent(fraction: fraction) == attendu)
    }

    @Test("Le texte du pourcentage utilise une espace insécable")
    func textePourcentage() {
        #expect(ReconstructionProgress.percentText(fraction: 0.42) == "42\u{00A0}%")
    }

    @Test("Le temps restant est arrondi à la minute supérieure", arguments: [
        (nil, nil),
        (0.0, ReconstructionProgress.RemainingTime.lessThanAMinute),
        (59.0, .lessThanAMinute),
        (60.0, .minutes(1)),
        (61.0, .minutes(2)),
        (90.0, .minutes(2)),
        (3540.0, .minutes(59)),
        (3600.0, .hours(1, minutes: 0)),
        (3900.0, .hours(1, minutes: 5)),
        (-5.0, nil),
        (Double.nan, nil),
    ] as [(Double?, ReconstructionProgress.RemainingTime?)])
    func tempsRestant(secondes: Double?, attendu: ReconstructionProgress.RemainingTime?) {
        #expect(ReconstructionProgress.remainingTime(seconds: secondes) == attendu)
    }

    @Test("Textes court et parlé")
    func textes() {
        #expect(ReconstructionProgress.RemainingTime.lessThanAMinute.text == "moins d'une minute")
        #expect(ReconstructionProgress.RemainingTime.minutes(1).text == "environ 1 min")
        #expect(ReconstructionProgress.RemainingTime.minutes(1).spokenText == "environ 1 minute")
        #expect(ReconstructionProgress.RemainingTime.minutes(2).spokenText == "environ 2 minutes")
        #expect(ReconstructionProgress.RemainingTime.hours(1, minutes: 5).text == "environ 1 h 05")
        #expect(ReconstructionProgress.RemainingTime.hours(2, minutes: 0).spokenText == "environ 2 heures")
    }

    @Test("La phrase VoiceOver combine pourcentage et temps restant")
    func phraseVoiceOver() {
        #expect(ReconstructionProgress.spokenText(fraction: 0.42, remainingSeconds: 90) == "42 pour cent, environ 2 minutes restantes")
        #expect(ReconstructionProgress.spokenText(fraction: 0.42, remainingSeconds: nil) == "42 pour cent")
    }
}
