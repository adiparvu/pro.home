import SwiftUI

// MARK: - Weather Widget (full-width, Revolut-style gradient)

struct WeatherWidget: View {
    var cityName: String
    var action: () -> Void

    @State private var shimmer = false

    var body: some View {
        Button(action: action) {
            TimelineView(.everyMinute) { ctx in
                ZStack {
                    LinearGradient(
                        colors: gradientColors(for: ctx.date),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )

                    LinearGradient(
                        colors: [.clear, .white.opacity(shimmer ? 0.10 : 0.03), .clear],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    .blendMode(.screen)

                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 8) {
                            Image(systemName: weatherIcon(for: ctx.date))
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(.white)
                                .symbolEffect(.pulse, options: .repeating)
                                .shadow(color: .white.opacity(0.35), radius: 12)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cityName.isEmpty ? "Proprietatea mea" : cityName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                Text("Apasă pentru prognoză")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                        .padding(.leading, 20)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(timeString(ctx.date))
                                .font(.system(size: 38, weight: .thin, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.2), radius: 4)
                            Text(dateString(ctx.date))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.80))
                        }
                        .padding(.trailing, 20)
                    }
                }
                .frame(height: 120)
            }
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: gradientColors(for: Date())[0].opacity(0.55), radius: 20, y: 8)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                shimmer = true
            }
        }
    }

    private func gradientColors(for date: Date) -> [Color] {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 5..<8:  return [Color(red: 0.90, green: 0.58, blue: 0.28), Color(red: 0.68, green: 0.38, blue: 0.76)]
        case 8..<18: return [Color(red: 0.18, green: 0.48, blue: 0.92), Color(red: 0.30, green: 0.72, blue: 0.95)]
        case 18..<21: return [Color(red: 0.78, green: 0.35, blue: 0.18), Color(red: 0.48, green: 0.22, blue: 0.62)]
        default:     return [Color(red: 0.04, green: 0.08, blue: 0.22), Color(red: 0.14, green: 0.18, blue: 0.42)]
        }
    }

    private func weatherIcon(for date: Date) -> String {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 5..<8:  return "sunrise.fill"
        case 8..<18: return "sun.max.fill"
        case 18..<21: return "sunset.fill"
        default:     return "moon.stars.fill"
        }
    }

    private func timeString(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: date)
    }

    private func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEE, d MMM"
        f.locale = .current
        return f.string(from: date)
    }
}

// MARK: - Calendar Large Widget (full-width, big date)

struct CalendarLargeWidget: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            TimelineView(.everyMinute) { ctx in
                HStack(spacing: 0) {
                    // Big day number
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dayNumber(ctx.date))
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.5), value: dayNumber(ctx.date))
                        Text(monthYear(ctx.date))
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.primary.opacity(0.45))
                    }
                    .padding(.leading, 20)

                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1, height: 60)
                        .padding(.horizontal, 18)

                    // Day name + mini week strip
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dayName(ctx.date))
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { offset in
                                let day = weekDay(ctx.date, offset: offset - weekdayOffset(ctx.date))
                                let isToday = Calendar.current.isDateInToday(day)
                                VStack(spacing: 2) {
                                    Text(weekDayLetter(day))
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundStyle(isToday ? .white : Color.primary.opacity(0.3))
                                    Text(dayNum(day))
                                        .font(.system(size: 12, weight: isToday ? .bold : .regular))
                                        .foregroundStyle(isToday ? .white : Color.primary.opacity(0.55))
                                }
                                .frame(width: 26, height: 36)
                                .background(isToday ? Color.accentColor : Color.clear,
                                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.vertical, 16)
            }
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 20)
    }

    private func dayNumber(_ date: Date) -> String {
        "\(Calendar.current.component(.day, from: date))"
    }

    private func monthYear(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; f.locale = .current
        return f.string(from: date)
    }

    private func dayName(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE"; f.locale = .current
        return f.string(from: date).capitalized
    }

    private func weekDay(_ from: Date, offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: from) ?? from
    }

    private func weekdayOffset(_ date: Date) -> Int {
        let weekday = Calendar.current.component(.weekday, from: date)
        return (weekday + 5) % 7  // Mon=0…Sun=6
    }

    private func weekDayLetter(_ date: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEEE"; f.locale = .current
        return f.string(from: date).uppercased()
    }

    private func dayNum(_ date: Date) -> String {
        "\(Calendar.current.component(.day, from: date))"
    }
}
