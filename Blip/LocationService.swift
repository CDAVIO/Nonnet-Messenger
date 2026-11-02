import CoreLocation
import Foundation

/// GPS position, elevation and compass heading. All work offline (no internet needed).
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var location: CLLocation?
    /// Degrees clockwise from true north, nil when the device has no compass (e.g. a Mac).
    @Published private(set) var heading: Double?
    /// The heading unwrapped (can go past 360 or below 0) so the dial never spins the long way round.
    @Published private(set) var dialRotation: Double = 0
    @Published private(set) var authorized = true

    var onUpdate: ((CLLocation) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.headingFilter = 1
        manager.requestWhenInUseAuthorization()
        start()
    }

    private func start() {
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        authorized = status != .denied && status != .restricted
        if status == .authorizedWhenInUse || status == .authorizedAlways { start() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        location = last
        onUpdate?(last)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let value = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        var delta = value - (heading ?? value)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        dialRotation += delta
        heading = value
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    // MARK: - Where is a peer?

    /// Angle on screen (radians, 0 = straight up, clockwise) toward the peer: UWB direction when available,
    /// otherwise the GPS bearing turned relative to where the phone points.
    /// Pass `heading` to use a smoothed value (the radar does); defaults to the live one.
    func screenAngle(for peer: Peer, heading: Double? = nil) -> Double? {
        // UWB: -z is straight out of the top of the phone, so atan2 keeps front and back apart.
        if let dir = peer.direction { return Double(atan2(dir.x, -dir.z)) }
        guard let mine = location, let theirs = peer.location else { return nil }
        return (Self.bearing(from: mine.coordinate, to: theirs.coordinate) - (heading ?? self.heading ?? 0)) * .pi / 180
    }

    func gpsDistance(to peer: Peer) -> Double? {
        guard let mine = location, let theirs = peer.location else { return nil }
        return mine.distance(from: theirs)
    }

    // MARK: - Formatting

    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func cardinal(_ degrees: Double) -> String {
        let names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return names[Int((degrees / 45).rounded()) % 8]
    }

    /// 44°24'44" N  26°11'49" E
    static func dms(_ c: CLLocationCoordinate2D) -> String {
        func part(_ value: Double, _ pos: String, _ neg: String) -> String {
            let v = abs(value)
            let d = Int(v), m = Int((v - Double(d)) * 60), s = Int(((v - Double(d)) * 60 - Double(m)) * 60)
            return "\(d)°\(String(format: "%02d", m))'\(String(format: "%02d", s))\" \(value >= 0 ? pos : neg)"
        }
        return "\(part(c.latitude, "N", "S"))  \(part(c.longitude, "E", "W"))"
    }
}
