import SwiftUI
import CoreLocation

// MARK: - Weather Widget (full-width, Revolut-style gradient + WeatherKit)

struct WeatherWidget: View {
    var cityName: String
    var coordinate: CLLocationCoordinate2D?
    var action: () -> Void

    @State private var weatherService = WeatherKitService.shared
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
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
                            Image(systemName: weatherService.currentWeather != nil
                                  ? weatherService.conditionSymbol
                                  : weatherIcon(for: ctx.date))
                                .font(AppFont.scaled(44, weight: .light))
                                .foregroundStyle(.white)
                                .symbolEffect(.pulse, options: .repeating)
                                .shadow(color: .white.opacity(0.35), radius: 12)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(cityName.isEmpty ? "Proprietatea mea" : cityName)
                                    .font(AppFont.subheadline)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                if let w = weatherService.currentWeather {
                                    Text(w.condition.description)
                                        .font(AppFont.scaled(11))
                                        .foregroundStyle(.white.opacity(0.65))
                                } else {
                                    Text("Tap for forecast")
                                        .font(AppFont.scaled(11))
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                            }
                        }
                        .padding(.leading, AppSpacing.xl)

                        Spacer()

                        VStack(alignment: .trailing, spacing: 4) {
                            if weatherService.currentWeather != nil {
                                Text(weatherService.temperatureString)
                                    .font(AppFont.scaled(38, weight: .thin, design: .rounded))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.2), radius: 4)
                                Text(weatherService.feelsLikeString)
                                    .font(AppFont.scaled(11))
                                    .foregroundStyle(.white.opacity(0.70))
                                Text(weatherService.humidityString)
                                    .font(AppFont.scaled(11))
                                    .foregroundStyle(.white.opacity(0.70))
                            } else {
                                Text(timeString(ctx.date))
                                    .font(AppFont.scaled(38, weight: .thin, design: .rounded))
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.2), radius: 4)
                                Text(dateString(ctx.date))
                                    .font(AppFont.caption)
                                    .foregroundStyle(.white.opacity(0.80))
                            }
                        }
                        .padding(.trailing, AppSpacing.xl)
                    }
                }
                .frame(height: 120)
                // Chrome inside the label so it scales WITH the pressed
                // card. The live time-of-day gradient is the widget's
                // honest content and stays; the lift is the page's shared
                // soft card shadow plus the standard hairline.
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)
                        .strokeBorder(Color.hairline, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
            }
        }
        .buttonStyle(SmartCardPressStyle())
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }
            if let coord = coordinate {
                Task { await WeatherKitService.shared.fetch(for: coord) }
            }
        }
    }

    private func gradientColors(for date: Date) -> [Color] {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case 5..<8:  return [Color(red: 0.90, green: 0.58, blue: 0.28), Color(red: 0.68, green: 0.38, blue: 0.76)]
        case 8..<18: return [Color(red: 0.18, green: 0.48, blue: 0.92), Color.brandSkyBlue]
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
    /// The next few HOUSE agenda entries (events, tasks, deadlines) — real
    /// data from the same aggregator the calendar page reads. Empty = the
    /// widget honestly shows just the date, no filler rows.
    var upcoming: [AgendaItem] = []
    var action: () -> Void

    var body: some View {
        Button {
            HapticFeedback.impact(.light)
            action()
        } label: {
            TimelineView(.everyMinute) { ctx in
                VStack(spacing: 0) {
                HStack(spacing: 0) {
                    // Big day number
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dayNumber(ctx.date))
                            .font(AppFont.scaled(72, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.5), value: dayNumber(ctx.date))
                        Text(monthYear(ctx.date))
                            .font(AppFont.scaled(13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.leading, AppSpacing.xl)

                    Rectangle()
                        .fill(Color.hairline)
                        .frame(width: 1, height: 60)
                        .padding(.horizontal, 18)

                    // Day name + mini week strip
                    VStack(alignment: .leading, spacing: 8) {
                        Text(dayName(ctx.date))
                            .font(AppFont.title3)
                            .foregroundStyle(.primary)

                        HStack(spacing: 6) {
                            ForEach(0..<7, id: \.self) { offset in
                                let day = weekDay(ctx.date, offset: offset - weekdayOffset(ctx.date))
                                let isToday = Calendar.current.isDateInToday(day)
                                VStack(spacing: 2) {
                                    // Today sits on the accent — white on it,
                                    // the system's own accent-fill contract.
                                    Text(weekDayLetter(day))
                                        .font(AppFont.scaled(9, weight: .medium))
                                        .foregroundStyle(isToday
                                            ? Color.white.opacity(AppOpacity.emphasis)
                                            : Color.secondary.opacity(0.6))
                                    Text(dayNum(day))
                                        .font(AppFont.scaled(12, weight: isToday ? .bold : .regular))
                                        .foregroundStyle(isToday ? Color.white : Color.secondary)
                                }
                                .frame(width: 26, height: 36)
                                .background(isToday ? Color.accentColor : Color.clear,
                                            in: RoundedRectangle(cornerRadius: AppRadius.sm, style: .continuous))
                            }
                        }
                    }

                    Spacer()
                }
                if !upcoming.isEmpty {
                    VStack(spacing: AppSpacing.xs) {
                        ForEach(upcoming) { item in
                            HStack(spacing: AppSpacing.sm) {
                                Circle()
                                    .fill(item.category.color)
                                    .frame(width: 6, height: 6)
                                Text(verbatim: item.title)
                                    .font(AppFont.scaled(12, weight: .medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer(minLength: AppSpacing.xs)
                                Text(verbatim: item.hasTime
                                     ? item.date.formatted(date: .omitted, time: .shortened)
                                     : item.date.formatted(.dateTime.day().month(.abbreviated)))
                                    .font(AppFont.scaled(11))
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                    .padding(.horizontal, AppSpacing.xl)
                    .padding(.top, AppSpacing.md)
                }
                }
                .padding(.vertical, AppSpacing.lg)
                // Inside the label so the glass scales WITH the pressed card.
                .liquidGlass(cornerRadius: AppRadius.xl)
            }
        }
        .buttonStyle(SmartCardPressStyle())
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
