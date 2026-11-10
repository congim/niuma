import Foundation

enum DigitRoller {
    static func offsets(value: Double, decimals: Int, speed: Double) -> [Double] {
        let value = max(0, value), decimals = min(6, max(0, decimals))
        let count = String(format: "%.0f", floor(value)).count + decimals
        let scaled = value * pow(10, Double(decimals)), scaledSpeed = speed * pow(10, Double(decimals))
        return (0..<count).map { index in
            let power = pow(10, Double(count - index - 1)), current = scaled / power + 1e-7
            let integer = floor(current), fraction = max(0, current - integer - 1e-7)
            let rate = scaledSpeed / power
            var offset = integer.truncatingRemainder(dividingBy: 10)
            if rate > 0 && rate <= 12 {
                let window = min(1, rate * 0.25), progress = min(1, max(0, (fraction - (1 - window)) / window))
                offset += progress * progress * (3 - 2 * progress)
            }
            return offset
        }
    }
}
