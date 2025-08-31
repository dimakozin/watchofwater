import SwiftUI

struct AnalogClockView: View {
    var date: Date
    var progress: Double // 0...1, уровень воды
    var waterText: String
    var isPouring: Bool = false
    var pourTimestamp: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let inset = size * 0.06
            let circleRect = CGRect(x: (geo.size.width - size)/2 + inset,
                                    y: (geo.size.height - size)/2 + inset,
                                    width: size - inset*2,
                                    height: size - inset*2)
            let center = CGPoint(x: circleRect.midX, y: circleRect.midY)

            ZStack {
                // Фон и контур сосуда
                Circle()
                    .fill(.background)
                    .frame(width: circleRect.width, height: circleRect.height)
                    .position(center)

                // Вода: реалистичное заполнение внутри круга
                WaterDisk(progress: progress, circleRect: circleRect, isPouring: isPouring, pourTimestamp: pourTimestamp)

                Circle()
                    .stroke(Color.secondary.opacity(0.35), lineWidth: 2)
                    .frame(width: circleRect.width, height: circleRect.height)
                    .position(center)

                // Часовые метки
                Ticks(count: 12, inner: circleRect.width * 0.5 * 0.80, outer: circleRect.width * 0.5 * 0.94)
                    .stroke(Color.secondary, lineWidth: 2)
                    .frame(width: circleRect.width, height: circleRect.height)
                    .position(center)

                // Стрелки
                HandsView(date: date)
                    .frame(width: circleRect.width, height: circleRect.height)
                    .position(center)

                // Значок капли при добавлении
                if isPouring {
                    Image(systemName: "drop.fill")
                        .foregroundStyle(.blue)
                        .font(.system(size: 18, weight: .semibold))
                        .padding(6)
                        .background(
                            Circle().fill(Color.blue.opacity(0.12))
                        )
                        .overlay(Circle().stroke(Color.blue.opacity(0.3), lineWidth: 1))
                        .position(x: center.x, y: circleRect.minY - 10)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct WaterDisk: View {
    var progress: Double
    var circleRect: CGRect
    var isPouring: Bool
    var pourTimestamp: Double?

    @State private var localImpulseStart: Double? = nil
    @AppStorage("softAnimations") private var softAnimations: Bool = false

    var body: some View {
        TimelineView(.animation) { ctx in
            let timeNow = ctx.date.timeIntervalSinceReferenceDate
            let t = CGFloat(timeNow)
            let clamped = CGFloat(min(max(progress, 0), 1))
            // 0 — пусто, 1 — полно
            let level = clamped

            // Импульс при наливе: экспоненциальное затухание амплитуды и наклона
            let start = pourTimestamp ?? localImpulseStart ?? (isPouring ? Double(t) : nil)
            let elapsed = start.map { max(0, CGFloat(Double(t) - $0)) } ?? .infinity
            let impulse = elapsed.isInfinite ? 0 : exp(-elapsed * (softAnimations ? 3.0 : 2.2))

            // Плавная, менее резкая волна: без базовой амплитуды после затухания
            let baseAmp = circleRect.width * (softAnimations ? 0.01 : 0.015)
            let amp = baseAmp * impulse
            let phase = t * ((softAnimations ? 0.5 : 0.6) + (softAnimations ? 0.4 : 0.6) * impulse)
            let tilt: Angle = .degrees(-6 * Double(impulse))

            let surfY = circleRect.maxY - circleRect.height * level
            let wavelength = max(circleRect.width / (softAnimations ? 1.2 : 1.6), 18)

            ZStack {
                // Заливка с волной, обрезанная по кругу
                RectWaveShape(minX: circleRect.minX, maxX: circleRect.maxX, baseY: surfY, wavelength: wavelength, amplitude: min(amp, circleRect.height * 0.08), phase: phase)
                    .fill(LinearGradient(colors: [Color.blue.opacity(0.9), Color.blue], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RectWaveShape(minX: circleRect.minX, maxX: circleRect.maxX, baseY: surfY, wavelength: wavelength, amplitude: min(amp * 0.6, circleRect.height * 0.06), phase: phase + .pi/2)
                            .fill(LinearGradient(colors: [Color.cyan.opacity(0.5), Color.blue.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                            .opacity(0.55)
                    )
                    .mask(
                        Circle()
                            .frame(width: circleRect.width, height: circleRect.height)
                            .position(x: circleRect.midX, y: circleRect.midY)
                    )
                    .rotationEffect(tilt)
                    .opacity(level > 0.001 ? 1 : 0)

                // Брызги при наливе: частицы вылетают и возвращаются в воду
                if impulse > 0.01 {
                    let origin = CGPoint(x: circleRect.midX + circleRect.width * 0.16, y: surfY - 2)
                    Splashes(startTime: start, now: timeNow, origin: origin, surfaceY: surfY)
                        .mask(
                            Circle()
                                .frame(width: circleRect.width, height: circleRect.height)
                                .position(x: circleRect.midX, y: circleRect.midY)
                        )
                        .opacity(0.95)
                }
            }
            .onChange(of: isPouring) { newValue in
                if newValue { localImpulseStart = Double(t) }
            }
        }
    }
}

private struct RectWaveShape: Shape {
    var minX: CGFloat
    var maxX: CGFloat
    var baseY: CGFloat
    var wavelength: CGFloat
    var amplitude: CGFloat
    var phase: CGFloat

    func path(in _: CGRect) -> Path {
        var p = Path()
        let minY = baseY
        p.move(to: CGPoint(x: minX, y: minY))
        var x = minX
        while x <= maxX {
            let rel = (x - minX) / wavelength
            let edge = (x - minX) / max(1, (maxX - minX))
            let atten = pow(sin(edge * .pi), 1.4) // мягче у стенок
            let y = minY + sin(rel * .pi * 2 + phase) * amplitude * atten
            p.addLine(to: CGPoint(x: x, y: y))
            x += 1
        }
        // Замыкание к низу прямоугольником (будет обрезан окружностью)
        p.addLine(to: CGPoint(x: maxX, y: minY + 2000))
        p.addLine(to: CGPoint(x: minX, y: minY + 2000))
        p.closeSubpath()
        return p
    }
}

private struct Splashes: View {
    var startTime: Double?
    var now: Double
    var origin: CGPoint
    var surfaceY: CGFloat

    var body: some View {
        Canvas { context, _ in
            guard let start = startTime else { return }
            let dt = max(0, now - start)
            // Жизнь брызг ~0.7с
            let life: Double = 0.7
            guard dt < life else { return }

            let t = dt
            let g: CGFloat = 900 // пикс/с^2 в canvas-единицах; визуальная гравитация
            let count = 7
            for i in 0..<count {
                // Псевдослучайные направления: веер +/- 70°
                let seed = Double((i+1) * 131)
                let angleDeg = -70 + (140.0 * Double(i) / Double(count-1)) + sin(seed) * 4
                let angle = CGFloat(angleDeg * .pi / 180)
                let speed: CGFloat = 260 + CGFloat(i) * 12 // пикс/с
                let vx = cos(angle) * speed
                let vy = sin(angle) * speed

                let px = origin.x + vx * CGFloat(t)
                let py = origin.y + vy * CGFloat(t) + 0.5 * g * CGFloat(t*t)

                // После пересечения с поверхностью — слегка тонем (исчезаем)
                if py > surfaceY + 1 { continue }

                let size: CGFloat = 3
                let rect = CGRect(x: px - size/2, y: py - size/2, width: size, height: size)
                let alpha = max(0, 1 - CGFloat(t / life))
                context.fill(Path(ellipseIn: rect), with: .color(Color.cyan.opacity(0.6 * alpha)))
            }
        }
    }
}

private struct Ticks: Shape {
    var count: Int
    var inner: CGFloat
    var outer: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for i in 0..<count {
            let angle = Double(i) / Double(count) * .pi * 2
            let dir = CGPoint(x: cos(angle), y: sin(angle))
            let p1 = CGPoint(x: center.x + dir.x * inner, y: center.y + dir.y * inner)
            let p2 = CGPoint(x: center.x + dir.x * outer, y: center.y + dir.y * outer)
            path.move(to: p1)
            path.addLine(to: p2)
        }
        return path
    }
}

private struct HandsView: View {
    var date: Date

    private var comps: DateComponents {
        Calendar.current.dateComponents([.hour, .minute], from: date)
    }

    private var hourAngle: Angle {
        let h = Double((comps.hour ?? 0) % 12)
        let m = Double(comps.minute ?? 0)
        return .radians(((h + m/60.0) / 12.0) * 2.0 * .pi)
    }

    private var minuteAngle: Angle {
        let m = Double(comps.minute ?? 0)
        return .radians((m / 60.0) * 2.0 * .pi)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            let hourLen = radius * 0.45
            let minuteLen = radius * 0.68

            ZStack {
                // Часовая стрелка
                Hand(length: hourLen, width: max(3, radius * 0.06))
                    .rotationEffect(hourAngle)

                // Минутная стрелка
                Hand(length: minuteLen, width: max(2, radius * 0.045))
                    .rotationEffect(minuteAngle)

                // Центральная ось
                Circle()
                    .fill(Color.primary)
                    .frame(width: max(4, radius * 0.09), height: max(4, radius * 0.09))
            }
            .frame(width: size, height: size)
        }
    }
}

private struct Hand: View {
    var length: CGFloat
    var width: CGFloat

    var body: some View {
        Capsule(style: .continuous)
            .frame(width: width, height: length)
            .offset(y: -length/2)
    }
}

#Preview {
    AnalogClockView(date: .now, progress: 0.6, waterText: "1200 / 2000 мл")
        .frame(width: 160, height: 160)
        .padding()
}
