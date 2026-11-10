import Foundation

extension CalculatorProvider {
    private struct Unit {
        let symbol: String
        let kind: String
        let scale: Double
        var offset = 0.0
        var inverse = false
        var names: [String] = []
        let targets: [String]

        func toBase(_ value: Double) -> Double { inverse ? scale / value : value * scale + offset }
        func fromBase(_ value: Double) -> Double { inverse ? scale / value : (value - offset) / scale }
    }

    private static let units: [Unit] = [
        Unit(symbol: "m", kind: "length", scale: 1, names: ["meter", "meters", "metre", "metres"], targets: ["km", "ft", "mi"]),
        Unit(symbol: "km", kind: "length", scale: 1_000, names: ["kilometer", "kilometers", "kilometre", "kilometres"], targets: ["m", "mi"]),
        Unit(symbol: "cm", kind: "length", scale: 0.01, names: ["centimeter", "centimeters", "centimetre", "centimetres"], targets: ["m", "in"]),
        Unit(symbol: "mm", kind: "length", scale: 0.001, names: ["millimeter", "millimeters", "millimetre", "millimetres"], targets: ["cm", "in"]),
        Unit(symbol: "µm", kind: "length", scale: 1e-6, names: ["micrometer", "micrometers", "micron", "microns"], targets: ["mm", "in"]),
        Unit(symbol: "nm", kind: "length", scale: 1e-9, names: ["nanometer", "nanometers", "nanometre", "nanometres"], targets: ["µm", "mm"]),
        Unit(symbol: "mi", kind: "length", scale: 1_609.344, names: ["mile", "miles"], targets: ["km", "m"]),
        Unit(symbol: "ft", kind: "length", scale: 0.3048, names: ["foot", "feet"], targets: ["m", "in"]),
        Unit(symbol: "in", kind: "length", scale: 0.0254, names: ["inch", "inches"], targets: ["cm", "ft"]),
        Unit(symbol: "yd", kind: "length", scale: 0.9144, names: ["yard", "yards"], targets: ["m", "ft"]),
        Unit(symbol: "nmi", kind: "length", scale: 1_852, names: ["nauticalmile", "nauticalmiles", "nautical mile", "nautical miles"],
            targets: ["km", "mi"]),

        Unit(symbol: "kg", kind: "mass", scale: 1, names: ["kilogram", "kilograms", "kilo", "kilos"], targets: ["lb", "g"]),
        Unit(symbol: "g", kind: "mass", scale: 0.001, names: ["gram", "grams"], targets: ["kg", "oz"]),
        Unit(symbol: "mg", kind: "mass", scale: 1e-6, names: ["milligram", "milligrams"], targets: ["g"]),
        Unit(symbol: "lb", kind: "mass", scale: 0.45359237, names: ["lbs", "pound", "pounds"], targets: ["kg", "oz"]),
        Unit(symbol: "oz", kind: "mass", scale: 0.028349523125, names: ["ounce", "ounces"], targets: ["g", "lb"]),
        Unit(symbol: "st", kind: "mass", scale: 6.35029318, names: ["stone", "stones"], targets: ["lb", "kg"]),
        Unit(symbol: "ton", kind: "mass", scale: 907.18474, names: ["tons"], targets: ["lb", "kg"]),
        Unit(symbol: "t", kind: "mass", scale: 1_000, names: ["tonne", "tonnes"], targets: ["kg", "lb"]),

        Unit(symbol: "°C", kind: "temperature", scale: 1, offset: 273.15, names: ["celsius", "centigrade"], targets: ["°F", "K"]),
        Unit(symbol: "°F", kind: "temperature", scale: 5 / 9, offset: 459.67 * 5 / 9, names: ["fahrenheit"], targets: ["°C", "K"]),
        Unit(symbol: "K", kind: "temperature", scale: 1, names: ["kelvin"], targets: ["°C", "°F"]),

        Unit(symbol: "L", kind: "volume", scale: 1, names: ["liter", "liters", "litre", "litres"], targets: ["ml", "gal"]),
        Unit(symbol: "ml", kind: "volume", scale: 0.001, names: ["milliliter", "milliliters", "millilitre", "millilitres"], targets: ["L", "fl oz"]),
        Unit(symbol: "gal", kind: "volume", scale: 3.785411784, names: ["gallon", "gallons"], targets: ["L", "fl oz"]),
        Unit(symbol: "qt", kind: "volume", scale: 0.946352946, names: ["quart", "quarts"], targets: ["L", "fl oz"]),
        Unit(symbol: "pt", kind: "volume", scale: 0.473176473, names: ["pint", "pints"], targets: ["L", "fl oz"]),
        Unit(symbol: "cup", kind: "volume", scale: 0.2365882365, names: ["cups"], targets: ["ml", "fl oz"]),
        Unit(symbol: "fl oz", kind: "volume", scale: 0.02957352956, names: ["floz", "fluid ounce", "fluid ounces"], targets: ["ml", "cup"]),
        Unit(symbol: "tbsp", kind: "volume", scale: 0.01478676478, names: ["tablespoon", "tablespoons"], targets: ["ml", "tsp"]),
        Unit(symbol: "tsp", kind: "volume", scale: 0.004928921594, names: ["teaspoon", "teaspoons"], targets: ["ml", "tbsp"]),

        Unit(symbol: "mph", kind: "speed", scale: 0.44704, targets: ["km/h", "m/s"]),
        Unit(symbol: "km/h", kind: "speed", scale: 1 / 3.6, names: ["kph", "kmh", "kmph"], targets: ["mph", "m/s"]),
        Unit(symbol: "m/s", kind: "speed", scale: 1, names: ["mps"], targets: ["km/h", "mph"]),
        Unit(symbol: "kn", kind: "speed", scale: 1_852 / 3_600, names: ["kt", "kts", "knot", "knots"], targets: ["km/h", "mph"]),

        Unit(symbol: "mpg", kind: "fuel", scale: 235.214583, inverse: true, targets: ["L/100km"]),
        Unit(symbol: "L/100km", kind: "fuel", scale: 1, names: ["l100km"], targets: ["mpg"]),

        Unit(symbol: "bytes", kind: "data", scale: 1, names: ["b", "byte"], targets: ["KB", "bits"]),
        Unit(symbol: "bits", kind: "data", scale: 0.125, names: ["bit"], targets: ["bytes"]),
        Unit(symbol: "KB", kind: "data", scale: 1e3, targets: ["MB", "bytes"]),
        Unit(symbol: "MB", kind: "data", scale: 1e6, targets: ["GB", "KB"]),
        Unit(symbol: "GB", kind: "data", scale: 1e9, targets: ["MB", "GiB"]),
        Unit(symbol: "TB", kind: "data", scale: 1e12, targets: ["GB", "TiB"]),
        Unit(symbol: "KiB", kind: "data", scale: 1_024, targets: ["MiB", "bytes"]),
        Unit(symbol: "MiB", kind: "data", scale: 1_048_576, targets: ["GiB", "MB"]),
        Unit(symbol: "GiB", kind: "data", scale: 1_073_741_824, targets: ["MiB", "GB"]),
        Unit(symbol: "TiB", kind: "data", scale: 1_099_511_627_776, targets: ["GiB", "TB"]),

        Unit(symbol: "Hz", kind: "frequency", scale: 1, names: ["hertz"], targets: ["kHz", "rpm"]),
        Unit(symbol: "kHz", kind: "frequency", scale: 1e3, targets: ["Hz", "MHz"]),
        Unit(symbol: "MHz", kind: "frequency", scale: 1e6, targets: ["kHz", "GHz"]),
        Unit(symbol: "GHz", kind: "frequency", scale: 1e9, targets: ["MHz", "Hz"]),
        Unit(symbol: "rpm", kind: "frequency", scale: 1 / 60, targets: ["Hz"]),

        Unit(symbol: "ms", kind: "time", scale: 0.001, names: ["msec", "millisecond", "milliseconds"], targets: ["sec"]),
        Unit(symbol: "sec", kind: "time", scale: 1, names: ["s", "secs", "second", "seconds"], targets: ["min", "hr"]),
        Unit(symbol: "min", kind: "time", scale: 60, names: ["mins", "minute", "minutes", "m"], targets: ["sec", "hr"]),
        Unit(symbol: "hr", kind: "time", scale: 3_600, names: ["h", "hrs", "hour", "hours"], targets: ["min", "days"]),
        Unit(symbol: "days", kind: "time", scale: 86_400, names: ["d", "day"], targets: ["hr", "min"]),
        Unit(symbol: "weeks", kind: "time", scale: 604_800, names: ["wk", "wks", "week"], targets: ["days", "hr"]),
        Unit(symbol: "months", kind: "time", scale: 2_629_800, names: ["month"], targets: ["days", "weeks"]),
        Unit(symbol: "years", kind: "time", scale: 31_557_600, names: ["yr", "yrs", "year"], targets: ["days", "months"]),

        Unit(symbol: "m²", kind: "area", scale: 1, names: ["sqm", "square meter", "square meters", "square metre", "square metres"],
            targets: ["ft²", "km²"]),
        Unit(symbol: "ft²", kind: "area", scale: 0.09290304, names: ["sqft", "square foot", "square feet"], targets: ["m²", "acres"]),
        Unit(symbol: "acres", kind: "area", scale: 4_046.8564224, names: ["acre"], targets: ["ft²", "m²"]),
        Unit(symbol: "ha", kind: "area", scale: 10_000, names: ["hectare", "hectares"], targets: ["m²", "acres"]),
        Unit(symbol: "km²", kind: "area", scale: 1e6, names: ["sqkm", "square kilometer", "square kilometers"], targets: ["m²", "mi²"]),
        Unit(symbol: "mi²", kind: "area", scale: 2_589_988.110336, names: ["sqmi", "square mile", "square miles"], targets: ["km²", "acres"]),

        Unit(symbol: "psi", kind: "pressure", scale: 6.8947572932, targets: ["kPa", "bar"]),
        Unit(symbol: "Pa", kind: "pressure", scale: 0.001, names: ["pascal", "pascals"], targets: ["kPa", "psi"]),
        Unit(symbol: "kPa", kind: "pressure", scale: 1, targets: ["psi", "bar"]),
        Unit(symbol: "bar", kind: "pressure", scale: 100, targets: ["kPa", "psi"]),
        Unit(symbol: "atm", kind: "pressure", scale: 101.325, targets: ["kPa", "psi"]),

        Unit(symbol: "N", kind: "force", scale: 1, names: ["newton", "newtons"], targets: ["lbf", "kgf"]),
        Unit(symbol: "lbf", kind: "force", scale: 4.4482216153, targets: ["N"]),
        Unit(symbol: "kgf", kind: "force", scale: 9.80665, targets: ["N", "lbf"]),

        Unit(symbol: "N m", kind: "torque", scale: 1, names: ["newtonmeter", "newtonmeters", "newton meter", "newton meters"],
            targets: ["lb-ft", "lb-in"]),
        Unit(symbol: "lb-ft", kind: "torque", scale: 1.3558179483, names: ["lbft", "ftlb", "ft-lb"], targets: ["N m"]),
        Unit(symbol: "lb-in", kind: "torque", scale: 0.112984829, names: ["lbin", "inlb", "in-lb"], targets: ["N m"]),

        Unit(symbol: "J", kind: "energy", scale: 1, names: ["joule", "joules"], targets: ["kJ", "kcal"]),
        Unit(symbol: "kJ", kind: "energy", scale: 1e3, targets: ["J", "kcal"]),
        Unit(symbol: "MJ", kind: "energy", scale: 1e6, targets: ["kJ", "kWh"]),
        Unit(symbol: "cal", kind: "energy", scale: 4.184, names: ["calorie", "calories"], targets: ["J", "kcal"]),
        Unit(symbol: "kcal", kind: "energy", scale: 4_184, targets: ["kJ", "cal"]),
        Unit(symbol: "Wh", kind: "energy", scale: 3_600, targets: ["J", "kWh"]),
        Unit(symbol: "kWh", kind: "energy", scale: 3.6e6, targets: ["Wh", "MJ"]),

        Unit(symbol: "W", kind: "power", scale: 1, names: ["watt", "watts"], targets: ["kW", "hp"]),
        Unit(symbol: "kW", kind: "power", scale: 1e3, names: ["kilowatt", "kilowatts"], targets: ["W", "hp"]),
        Unit(symbol: "hp", kind: "power", scale: 745.6998716, names: ["horsepower"], targets: ["W", "kW"]),

        Unit(symbol: "A", kind: "current", scale: 1, names: ["amp", "amps", "ampere", "amperes"], targets: ["mA"]),
        Unit(symbol: "mA", kind: "current", scale: 0.001, names: ["milliamp", "milliamps"], targets: ["A"]),
        Unit(symbol: "V", kind: "voltage", scale: 1, names: ["volt", "volts"], targets: ["mV", "kV"]),
        Unit(symbol: "mV", kind: "voltage", scale: 0.001, names: ["millivolt", "millivolts"], targets: ["V"]),
        Unit(symbol: "kV", kind: "voltage", scale: 1e3, names: ["kilovolt", "kilovolts"], targets: ["V"]),
        Unit(symbol: "Ω", kind: "resistance", scale: 1, names: ["ohm", "ohms"], targets: ["kΩ", "MΩ"]),
        Unit(symbol: "kΩ", kind: "resistance", scale: 1e3, names: ["kohm", "kiloohm"], targets: ["Ω", "MΩ"]),
        Unit(symbol: "MΩ", kind: "resistance", scale: 1e6, names: ["megaohm", "megohm"], targets: ["kΩ", "Ω"]),

        Unit(symbol: "deg", kind: "angle", scale: .pi / 180, names: ["degree", "degrees"], targets: ["rad"]),
        Unit(symbol: "rad", kind: "angle", scale: 1, names: ["radian", "radians"], targets: ["deg"]),

        Unit(symbol: "px", kind: "type", scale: 1, names: ["pixel", "pixels"], targets: ["pt", "rem"]),
        Unit(symbol: "pt", kind: "type", scale: 4.0 / 3, names: ["pts", "point", "points"], targets: ["px", "pica"]),
        Unit(symbol: "rem", kind: "type", scale: 16, names: ["em"], targets: ["px", "pt"]),
        Unit(symbol: "pica", kind: "type", scale: 16, names: ["picas"], targets: ["pt", "px"]),

        Unit(symbol: "m/s²", kind: "acceleration", scale: 1, names: ["mps2"], targets: ["g", "ft/s²"]),
        Unit(symbol: "g", kind: "acceleration", scale: 9.80665, names: ["gforce", "gee"], targets: ["m/s²"]),
        Unit(symbol: "ft/s²", kind: "acceleration", scale: 0.3048, targets: ["m/s²"]),

        Unit(symbol: "kg/m³", kind: "density", scale: 1, names: ["kgm3"], targets: ["lb/ft³", "g/cm³"]),
        Unit(symbol: "lb/ft³", kind: "density", scale: 16.01846337, names: ["lbft3"], targets: ["kg/m³"]),
        Unit(symbol: "g/cm³", kind: "density", scale: 1e3, targets: ["kg/m³"])
    ]

    private static func unitKey(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "²", with: "2")
            .replacingOccurrences(of: "³", with: "3")
            .replacingOccurrences(of: "µ", with: "u")
            .trimmingCharacters(in: .whitespaces)
    }

    private static let unitsByName: [String: [Unit]] = units.reduce(into: [:]) { index, unit in
        for name in [unit.symbol] + unit.names {
            index[unitKey(name), default: []].append(unit)
        }
    }

    private static let unitQuery = try! NSRegularExpression(pattern: "^(" + numberPattern + #")\s*(\D.*)$"#)
    private static let unitPart = try! NSRegularExpression(pattern: "(" + numberPattern + #")\s*([^\d\s][^\d]*?)\s*(?=[-+]?\d|$)"#)
    private static let unitSeparator = try! NSRegularExpression(pattern: #"\s(?:to|in|into|as)(?=\s)"#)
    private static let unitMarks: [(pattern: String, replacement: String)] = [
        (#"(\d)\s*['′]\s*(\d+(?:\.\d+)?)\s*(?:"|″|'')?"#, "$1 ft $2 in "),
        (#"(\d)\s*['′]"#, "$1 ft "),
        (#"(\d)\s*["″]"#, "$1 in "),
        (#"^(?:convert|what is|what's|whats)\s+"#, ""),
        (#"\s+"#, " ")
    ]

    private struct Quantity {
        let base: Double
        let unit: Unit
        let label: String
        var isCompound = false
    }

    private static func quantity(_ text: String, convertingTo target: String?) -> Quantity? {
        let whole = NSRange(text.startIndex..<text.endIndex, in: text)
        let targetKinds = target.flatMap { unitsByName[$0] }?.map(\.kind)
        func unit(named name: String, among kinds: [String]?) -> Unit? {
            unitsByName[unitKey(name)]?.first { kinds?.contains($0.kind) ?? true }
        }
        if let match = unitQuery.firstMatch(in: text, range: whole),
           let valueRange = Range(match.range(at: 1), in: text), let nameRange = Range(match.range(at: 2), in: text),
           let value = numberValue(String(text[valueRange])), let unit = unit(named: String(text[nameRange]), among: targetKinds) {
            return Quantity(base: unit.toBase(value), unit: unit, label: "\(formatConversion(value)) \(unit.symbol)")
        }

        var parts: [(value: Double, name: String)] = []
        var end = text.startIndex
        for match in unitPart.matches(in: text, range: whole) {
            guard let range = Range(match.range, in: text), range.lowerBound == end,
                  let valueRange = Range(match.range(at: 1), in: text), let nameRange = Range(match.range(at: 2), in: text),
                  let value = numberValue(String(text[valueRange])) else { return nil }
            parts.append((value, String(text[nameRange])))
            end = text[range.upperBound...].firstIndex { $0 != " " } ?? text.endIndex
        }
        guard parts.count > 1, end == text.endIndex else { return nil }
        let kinds = parts.map { part in Set((unitsByName[unitKey(part.name)] ?? []).filter { $0.offset == 0 && $0.inverse == false }.map(\.kind)) }
        let shared = kinds.dropFirst().reduce(kinds[0]) { $0.intersection($1) }.filter { targetKinds?.contains($0) ?? true }
        let resolved = parts.compactMap { part in unit(named: part.name, among: Array(shared)).map { (part.value, $0) } }
        guard let first = resolved.first, resolved.count == parts.count, resolved.allSatisfy({ $0.1.kind == first.1.kind }) else { return nil }
        return Quantity(
            base: resolved.reduce(0) { $0 + $1.1.toBase($1.0) },
            unit: first.1,
            label: resolved.map { "\(formatConversion($0.0)) \($0.1.symbol)" }.joined(separator: " "),
            isCompound: true
        )
    }

    static func convert(_ query: String) -> [CalculatorEvaluation] {
        let text = unitMarks.reduce(unitKey(query)) {
            $0.replacingOccurrences(of: $1.pattern, with: $1.replacement, options: .regularExpression)
        }.trimmingCharacters(in: .whitespaces)

        var source = quantity(text, convertingTo: nil)
        var targets = source.map { quantity in
            quantity.unit.targets.compactMap { name in unitsByName[unitKey(name)]?.first { $0.kind == quantity.unit.kind } }
        }
        if source == nil {
            for split in unitSeparator.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed() {
                guard let range = Range(split.range, in: text) else { continue }
                let targetName = unitKey(String(text[range.upperBound...]))
                guard let quantity = quantity(String(text[..<range.lowerBound]), convertingTo: targetName),
                      let target = unitsByName[targetName]?.first(where: { $0.kind == quantity.unit.kind }),
                      quantity.isCompound || target.symbol != quantity.unit.symbol else { continue }
                source = quantity
                targets = [target]
                break
            }
        }

        guard let source, let targets else { return [] }
        return targets.compactMap { target in
            let converted = target.fromBase(source.base)
            guard converted.isFinite else { return nil }
            let result = "\(formatConversion(converted)) \(target.symbol)"
            return CalculatorEvaluation(expression: source.label, result: result, copyValue: result)
        }
    }
}
