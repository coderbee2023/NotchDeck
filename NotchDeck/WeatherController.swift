import AppKit
import Combine
import CoreLocation

enum WeatherCondition: String {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, snow, thunder

    var symbol: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .cloudy: return "cloud.fill"
        case .fog: return "cloud.fog.fill"
        case .drizzle: return "cloud.drizzle.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "snowflake"
        case .thunder: return "cloud.bolt.rain.fill"
        }
    }

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly Cloudy"
        case .cloudy: return "Cloudy"
        case .fog: return "Fog"
        case .drizzle: return "Drizzle"
        case .rain: return "Rain"
        case .snow: return "Snow"
        case .thunder: return "Storm"
        }
    }

    static func from(code: Int) -> WeatherCondition {
        switch code {
        case 0: return .clear
        case 1, 2: return .partlyCloudy
        case 3: return .cloudy
        case 45, 48: return .fog
        case 51, 53, 55, 56, 57: return .drizzle
        case 61, 63, 65, 66, 67, 80, 81, 82: return .rain
        case 71, 73, 75, 77, 85, 86: return .snow
        case 95, 96, 99: return .thunder
        default: return .cloudy
        }
    }
}

struct WeatherHour: Identifiable {
    let id = UUID()
    let date: Date
    let celsius: Double
    let condition: WeatherCondition
}

final class WeatherController: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var celsius: Double?
    @Published private(set) var feelsLike: Double?
    @Published private(set) var condition: WeatherCondition?
    @Published private(set) var isDay = true
    @Published private(set) var hours: [WeatherHour] = []
    @Published private(set) var place: String?
    @Published private(set) var problem: String?
    @Published private(set) var updated: Date?

    private var settings: DeckSettings?
    private let manager = CLLocationManager()
    private var coords: CLLocationCoordinate2D?
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var askedForLocation = false

    var temperature: Double? {
        guard let celsius else { return nil }
        return (settings?.fahrenheit ?? false) ? celsius * 9 / 5 + 32 : celsius
    }

    var unit: String { (settings?.fahrenheit ?? false) ? "°F" : "°C" }

    func display(_ c: Double) -> String {
        let v = (settings?.fahrenheit ?? false) ? c * 9 / 5 + 32 : c
        return "\(Int(v.rounded()))°"
    }

    var summary: String? {
        guard let celsius, let condition else { return nil }
        let head = "\(display(celsius)) · \(condition.label)"
        guard let next = hours.first(where: { $0.date > Date() }) else { return head }
        let fmt = DateFormatter()
        fmt.dateFormat = "HH"
        return head + " · \(fmt.string(from: next.date))h \(display(next.celsius)) \(next.condition.label.lowercased())"
    }

    func start(settings: DeckSettings) {
        self.settings = settings
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer

        settings.$weatherOn.dropFirst().receive(on: RunLoop.main).sink { [weak self] on in
            if on { self?.refresh(force: true) } else { self?.clear() }
        }.store(in: &cancellables)
        settings.$weatherCity.dropFirst().debounce(for: .seconds(0.6), scheduler: RunLoop.main).sink { [weak self] _ in
            self?.coords = nil
            self?.refresh(force: true)
        }.store(in: &cancellables)
        settings.$weatherUseLocation.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            self?.coords = nil
            self?.refresh(force: true)
        }.store(in: &cancellables)

        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
        refresh(force: true)
    }

    private func clear() {
        celsius = nil
        condition = nil
        hours = []
        place = nil
        problem = nil
    }

    func refresh(force: Bool = false) {
        guard let settings, settings.weatherOn else { return }
        if !force, let updated, Date().timeIntervalSince(updated) < 600 { return }

        if let c = coords {
            fetch(c)
            return
        }
        if settings.weatherUseLocation {
            let status = manager.authorizationStatus
            switch status {
            case .authorized, .authorizedAlways:
                if let loc = manager.location {
                    coords = loc.coordinate
                    fetch(loc.coordinate)
                } else {
                    manager.requestLocation()
                }
                return
            case .notDetermined:
                if !askedForLocation {
                    askedForLocation = true
                    manager.requestWhenInUseAuthorization()
                }
                geocodeCityIfPossible()
                return
            default:
                geocodeCityIfPossible()
                return
            }
        }
        geocodeCityIfPossible()
    }

    private func geocodeCityIfPossible() {
        guard let city = settings?.weatherCity.trimmingCharacters(in: .whitespaces), !city.isEmpty else {
            problem = (settings?.weatherUseLocation ?? false) ? "Waiting for location — or set a city" : "Set a city for weather"
            return
        }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1")]
        guard let url = c.url else { return }
        URLSession.shared.dataTask(with: URLRequest(url: url, timeoutInterval: 10)) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let results = obj["results"] as? [[String: Any]],
                  let first = results.first,
                  let lat = first["latitude"] as? Double,
                  let lon = first["longitude"] as? Double else {
                DispatchQueue.main.async { self.problem = "Couldn't find that city" }
                return
            }
            let name = (first["name"] as? String) ?? city
            DispatchQueue.main.async {
                self.place = name
                self.coords = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                self.fetch(self.coords!)
            }
        }.resume()
    }

    private func fetch(_ c: CLLocationCoordinate2D) {
        var comp = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comp.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", c.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", c.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,precipitation,cloud_cover"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "forecast_hours", value: "6"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = comp.url else { return }
        // Always pull a fresh reading — never serve a cached HTTP response, or the notch can show stale weather.
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        URLSession.shared.dataTask(with: request) { [weak self] data, _, err in
            guard let self else { return }
            guard let data, let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let cur = obj["current"] as? [String: Any] else {
                DispatchQueue.main.async { self.problem = err == nil ? "Weather service didn't answer" : "No network for weather" }
                return
            }
            let temp = cur["temperature_2m"] as? Double
            let feels = cur["apparent_temperature"] as? Double
            let code = (cur["weather_code"] as? Int) ?? 3
            let day = ((cur["is_day"] as? Int) ?? 1) == 1
            let precip = (cur["precipitation"] as? Double) ?? 0
            let clouds = (cur["cloud_cover"] as? Double) ?? 100

            // The forecast model sometimes tags "showers"/"rain"/"thunder" while nothing is actually
            // falling. If there's no measurable precipitation, trust the sky instead of the code —
            // otherwise a dry sunny sky reads as rain in the notch.
            var current = WeatherCondition.from(code: code)
            if (current == .rain || current == .drizzle || current == .thunder), precip < 0.1 {
                current = clouds >= 60 ? .cloudy : (clouds >= 25 ? .partlyCloudy : .clear)
            }
            // Reconcile the code with the actual sky so it reads like a real forecast:
            // some clouds over a "clear" code → partly cloudy; a packed sky over "partly" → cloudy.
            if current == .clear && clouds >= 40 { current = .partlyCloudy }
            if current == .partlyCloudy && clouds >= 85 { current = .cloudy }

            var list: [WeatherHour] = []
            if let hourly = obj["hourly"] as? [String: Any],
               let times = hourly["time"] as? [String],
               let temps = hourly["temperature_2m"] as? [Double],
               let codes = hourly["weather_code"] as? [Int] {
                let fmt = DateFormatter()
                fmt.dateFormat = "yyyy-MM-dd'T'HH:mm"
                fmt.timeZone = TimeZone.current
                for i in 0..<min(times.count, min(temps.count, codes.count)) {
                    guard let d = fmt.date(from: times[i]) else { continue }
                    list.append(WeatherHour(date: d, celsius: temps[i], condition: .from(code: codes[i])))
                }
            }

            DispatchQueue.main.async {
                self.celsius = temp
                self.feelsLike = feels
                self.condition = current
                self.isDay = day
                self.hours = list
                self.updated = Date()
                self.problem = nil
            }
        }.resume()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        coords = loc.coordinate
        place = nil
        fetch(loc.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        geocodeCityIfPossible()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        default:
            geocodeCityIfPossible()
        }
    }

    static func askForCity(current: String, completion: @escaping (String) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Weather location"
        alert.informativeText = "Type the city NotchDeck should show the weather for."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = current
        field.placeholderString = "Tunis"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            completion(field.stringValue.trimmingCharacters(in: .whitespaces))
        }
    }
}
