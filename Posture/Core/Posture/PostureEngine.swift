import Foundation

/// Turns raw AirPods motion into a posture reading that knows its context.
///
/// The engine never looks at yaw: it works on the gravity vector in the
/// headphone frame, which does not change when the chair rotates. Everything
/// is measured against a calibrated baseline plus a small, bounded auto-zero.
///
/// The central idea is that the *way* the head leaves the good band says
/// more than the angle it ends up at:
///
/// - a fast nod that keeps the head at the same height is a deliberate
///   look-down (notes, book, tablet) and gets a long leash,
/// - a slow drift is postural creep and is what the coach is for,
/// - a fast pitch with the head dropping is a slump.
///
/// Instead of hard timers the engine fills a leaky "slouch load". Short dips
/// never fill it, repeated dips add up, and good posture drains it.
struct PostureEngine {
    var tuning: PostureTuning
    private(set) var anchor: Baseline?
    private(set) var offsetForward = 0.0
    private(set) var offsetLateral = 0.0

    // Filters
    private var lastT: TimeInterval?
    private var absForward = 0.0
    private var absLateral = 0.0
    private var fastForward = 0.0
    private var pitch = 0.0
    private var roll = 0.0
    private var pitchRate = 0.0
    private var peakRate = 0.0
    private var liveliness = 0.0
    private var bodyMotion = 0.0
    private var verticalVelocity = 0.0
    private var sink = 0.0

    // Output state
    private var score = 100.0
    private var load = 0.0
    private var zone: PostureZone = .aligned

    // Body movement
    private var movingFor = 0.0
    private var stillFor = 0.0
    private var isMoving = false
    private var isAway = false
    private var settleUntil = -Double.infinity
    private var rebasePending = false
    private var settleSumForward = 0.0
    private var settleSumLateral = 0.0
    private var settleCount = 0
    private var phoneUntil = -Double.infinity

    // Current excursion out of the good band
    private var entry: EntryKind = .none
    private var entryDecideAt: TimeInterval?
    private var entryPitch = 0.0
    private var excursionPeak = 0.0
    private var excursionSink = 0.0
    private var dwell = 0.0
    private var reclineFor = 0.0

    // Good <-> bad state and reminders
    private var isBad = false
    private var reminders = 0
    private var lastNudgeT = -Double.infinity
    private var alignedFor = 0.0

    init(tuning: PostureTuning = PostureTuning(), anchor: Baseline? = nil) {
        self.tuning = tuning
        self.anchor = anchor
    }

    // MARK: Commands

    /// Takes the current pose as the new upright reference ("Upright set").
    mutating func setUprightNow() {
        guard lastT != nil else { return }
        anchor = Baseline(forward: absForward, lateral: absLateral, capturedAt: Date(), isProvisional: false)
        offsetForward = 0
        offsetLateral = 0
        pitch = 0
        roll = 0
        load = 0
        score = 100
        zone = .aligned
        closeExcursion()
        isBad = false
        reminders = 0
    }

    /// Suspends scoring for a while, for example during a guided reset.
    mutating func hold(seconds: Double) {
        guard let t = lastT else { return }
        phoneUntil = max(phoneUntil, t + seconds)
    }

    // MARK: Ingest

    mutating func ingest(_ s: HeadSample, phone: PhoneContext = PhoneContext()) -> PostureReading {
        let g = s.gravity.normalized
        let f = atan2(g.y, -g.z) * 180 / .pi * tuning.forwardSign
        let l = atan2(g.x, -g.z) * 180 / .pi * tuning.lateralSign

        guard let last = lastT, s.t > last, s.t - last < 2 else {
            restart(at: s.t, forward: f, lateral: l)
            return reading(t: s.t, dt: 0, context: .settling, scored: false, events: [])
        }
        let dt = min(s.t - last, 0.25)
        lastT = s.t
        var events: [PostureEvent] = []
        let base = anchor ?? Baseline(forward: f, lateral: l, capturedAt: Date(), isProvisional: true)

        // 1. Filters
        absForward += alpha(dt, 0.35) * (f - absForward)
        absLateral += alpha(dt, 0.35) * (l - absLateral)
        let previousFast = fastForward
        fastForward += alpha(dt, 0.10) * (f - fastForward)
        pitchRate += alpha(dt, 0.12) * ((fastForward - previousFast) / dt - pitchRate)
        peakRate = max(abs(pitchRate), peakRate * exp(-dt / 1.5))
        pitch = absForward - base.forward - offsetForward
        roll = absLateral - base.lateral - offsetLateral

        let omega = s.rotationRate.length * 180 / .pi
        liveliness += alpha(dt, 6) * (omega - liveliness)
        bodyMotion += alpha(dt, 1.0) * (s.userAcceleration.length - bodyMotion)

        // Leaky double integration of the vertical acceleration. Useless for
        // slow drift, good enough to see the head drop during a quick slump.
        let up = -s.userAcceleration.dot(g) * 9.81
        verticalVelocity = verticalVelocity * exp(-dt / 1.0) + up * dt
        sink = sink * exp(-dt / 2.5) + verticalVelocity * dt

        // 2. Body movement: standing up, walking off, sitting back down
        if bodyMotion > tuning.movingAcceleration {
            movingFor += dt
            stillFor = 0
        } else {
            stillFor += dt
        }
        if !isMoving, movingFor >= tuning.movingConfirm {
            isMoving = true
            closeExcursion()
            // Getting up ends a bad spell without a sound.
            isBad = false
        }
        if isMoving, !isAway, movingFor >= tuning.awayAfter {
            isAway = true
            events.append(.away)
        }
        if stillFor >= 1.5 {
            if isMoving {
                isMoving = false
                if isAway {
                    isAway = false
                    events.append(.returned)
                }
                beginSettle(at: s.t)
            }
            movingFor = 0
        }

        // 3. Sitting back down: adopt the new seat as baseline, within bounds
        if rebasePending {
            if s.t >= settleUntil {
                rebasePending = false
                if settleCount > 0 {
                    let cf = settleSumForward / Double(settleCount) - base.forward
                    let cl = settleSumLateral / Double(settleCount) - base.lateral
                    if cf > -12, cf < 6, abs(cl) < 8 {
                        offsetForward = clamp(cf, -tuning.maxBackOffset, tuning.maxForwardOffset)
                        offsetLateral = clamp(cl, -tuning.maxLateralOffset, tuning.maxLateralOffset)
                        pitch = absForward - base.forward - offsetForward
                        roll = absLateral - base.lateral - offsetLateral
                        events.append(.rebaselined)
                    }
                }
            } else if s.t >= settleUntil - 3, omega < 12 {
                settleSumForward += absForward
                settleSumLateral += absLateral
                settleCount += 1
            }
        }

        // 4. Phone usage
        let phoneBusy = phone.isInUse
        if phoneBusy { phoneUntil = max(phoneUntil, s.t + tuning.phoneHoldOff) }

        // 5. Excursion tracking: how did the head leave the good band?
        let forward = max(pitch, 0)
        let back = max(-pitch, 0)
        if entry == .none {
            if forward > tuning.goodBand, !isMoving, s.t >= settleUntil {
                entry = .ambiguous
                entryDecideAt = s.t + 0.6
                entryPitch = forward
                excursionPeak = peakRate
                excursionSink = sink
                dwell = 0
            }
        } else if forward < tuning.goodBand - tuning.hysteresis {
            closeExcursion()
        } else if let decideAt = entryDecideAt {
            excursionPeak = max(excursionPeak, abs(pitchRate))
            excursionSink = min(excursionSink, sink)
            if s.t >= decideAt {
                entry = classifyEntry()
                entryDecideAt = nil
            }
        } else if entry != .glance, pitchRate >= tuning.glanceRate, forward >= entryPitch + 8 {
            // Looked down from an already forward posture.
            entry = .glance
            dwell = 0
        }

        // 6. Context
        let context: PostureContext
        if isAway {
            context = .away
        } else if isMoving {
            context = .moving
        } else if phoneBusy {
            context = .phone
        } else if s.t < settleUntil || s.t < phoneUntil {
            context = .settling
        } else if entry == .glance {
            context = .lookingDown
        } else {
            context = .focused
        }
        let scored = context == .focused || context == .lookingDown

        if scored {
            if entry != .none { dwell += dt }
            reclineFor = back > tuning.goodBand + 4 ? reclineFor + dt : 0
        }

        // 7. Effective deviation and how much the context lets it count
        let lateralPart = max(abs(roll) - 2, 0) * 0.8
        let backPart = reclineFor > tuning.reclineGrace ? back * 0.5 : 0
        let sagittal = max(forward, backPart)
        let deviation = (sagittal * sagittal + lateralPart * lateralPart).squareRoot()

        var gain: Double
        var kind: NudgeKind = .slouch
        switch entry {
        case .none:
            if lateralPart > sagittal {
                gain = 0.7
                kind = .tilt
            } else if backPart > 0 {
                gain = 0.4
                kind = .recline
            } else {
                gain = 0
            }
        case .creep, .slump:
            gain = 1
        case .ambiguous:
            gain = 0.6
        case .glance:
            let over = clamp((dwell - tuning.lookDownBudget) / tuning.lookDownRamp, 0, 1)
            gain = 0.1 + 0.4 * over
            kind = .neck
        }
        // A head that keeps moving is reading, writing or talking. A frozen
        // head is either concentrating or collapsed, so it counts in full.
        if entry != .none {
            if liveliness > 12 {
                gain *= 0.5
            } else if entry == .glance, liveliness > 4 {
                gain *= 0.6
            }
        }

        let effective = deviation <= tuning.goodBand
            ? deviation
            : tuning.goodBand + (deviation - tuning.goodBand) * min(gain, 1)

        // 8. Score and zone. The live score keeps following the head while
        // the phone is in use, it just does not count.
        if context != .moving, context != .away {
            score += alpha(dt, 2.0) * (PostureScore.value(forDeviation: effective) - score)
            updateZone(effective)
        }

        // 9. Slouch load
        if !scored {
            load = max(0, load - dt / 40)
        } else if deviation > tuning.goodBand {
            if gain > 0 {
                let severity = clamp((deviation - tuning.goodBand) / (tuning.severeDeviation - tuning.goodBand), 0, 1)
                load = min(1, load + dt * gain * (0.4 + 0.6 * severity) / tuning.graceSeconds)
            }
        } else {
            load = max(0, load - dt / tuning.recoverSeconds)
        }

        if scored {
            alignedFor = zone == .aligned ? alignedFor + dt : 0
        }

        // 10. Good <-> bad. The two events always come as a pair: turning bad
        // emits a level 0 nudge, turning good again emits `.recovered`, with
        // no cooldown between spells. Only the reminders while a spell lasts
        // back off, each one doubling the wait.
        if scored, load >= 1 {
            if !isBad {
                isBad = true
                reminders = 0
                lastNudgeT = s.t
                events.append(.nudge(kind, level: 0))
            } else {
                let baseCooldown = kind == .neck ? tuning.neckCooldown : tuning.nudgeCooldown
                let cooldown = baseCooldown * pow(2, Double(min(reminders, 3)))
                if s.t - lastNudgeT >= cooldown {
                    reminders += 1
                    lastNudgeT = s.t
                    events.append(.nudge(kind, level: reminders))
                }
            }
        }
        if isBad, scored, alignedFor >= tuning.recoveryConfirm {
            isBad = false
            events.append(.recovered)
        }

        // 11. Auto-zero while quietly aligned
        if scored, entry == .none, abs(pitch) < tuning.autoZeroBand, abs(roll) < tuning.autoZeroBand, liveliness < 8 {
            let tau = pitch < 0 ? tuning.uprightTau : tuning.forwardTau
            offsetForward = clamp(offsetForward + pitch * dt / tau, -tuning.maxBackOffset, tuning.maxForwardOffset)
            offsetLateral = clamp(offsetLateral + roll * dt / 150, -tuning.maxLateralOffset, tuning.maxLateralOffset)
        }

        return reading(t: s.t, dt: dt, context: context, scored: scored, events: events)
    }

    // MARK: Internals

    private mutating func restart(at t: TimeInterval, forward f: Double, lateral l: Double) {
        lastT = t
        absForward = f
        absLateral = l
        fastForward = f
        if anchor == nil {
            anchor = Baseline(forward: f, lateral: l, capturedAt: Date(), isProvisional: true)
        }
        if let base = anchor {
            pitch = f - base.forward - offsetForward
            roll = l - base.lateral - offsetLateral
        }
        pitchRate = 0
        peakRate = 0
        verticalVelocity = 0
        sink = 0
        bodyMotion = 0
        movingFor = 0
        stillFor = 0
        isMoving = false
        isAway = false
        rebasePending = false
        closeExcursion()
        // Give the filters a moment before anything counts.
        phoneUntil = max(phoneUntil, t + 1.5)
    }

    private mutating func beginSettle(at t: TimeInterval) {
        settleUntil = t + tuning.settleSeconds
        rebasePending = true
        settleSumForward = 0
        settleSumLateral = 0
        settleCount = 0
        closeExcursion()
    }

    private mutating func closeExcursion() {
        entry = .none
        entryDecideAt = nil
        dwell = 0
    }

    private func classifyEntry() -> EntryKind {
        if excursionPeak >= tuning.glanceRate {
            return excursionSink < -tuning.slumpSink ? .slump : .glance
        }
        return excursionPeak <= tuning.creepRate ? .creep : .ambiguous
    }

    private mutating func updateZone(_ effective: Double) {
        let h = tuning.hysteresis
        switch zone {
        case .aligned:
            if effective > tuning.slouchBand + h {
                zone = .slouching
            } else if effective > tuning.goodBand + h {
                zone = .drifting
            }
        case .drifting:
            if effective < tuning.goodBand - h {
                zone = .aligned
            } else if effective > tuning.slouchBand + h {
                zone = .slouching
            }
        case .slouching:
            if effective < tuning.goodBand - h {
                zone = .aligned
            } else if effective < tuning.slouchBand - h {
                zone = .drifting
            }
        }
    }

    private func reading(t: TimeInterval, dt: TimeInterval, context: PostureContext, scored: Bool, events: [PostureEvent]) -> PostureReading {
        PostureReading(
            t: t,
            dt: dt,
            pitch: pitch,
            roll: roll,
            score: score,
            zone: zone,
            context: context,
            entry: entry,
            load: load,
            isScored: scored,
            events: events
        )
    }

    private func alpha(_ dt: Double, _ tau: Double) -> Double { 1 - exp(-dt / tau) }

    private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
}
