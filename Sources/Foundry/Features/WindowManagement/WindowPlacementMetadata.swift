import FoundryDomain

struct WindowPlacementMetadata {
    let title: String
    let subtitle: String
    let successMessage: String
    let aliases: [String]
    let icon: String
    let fallback: String

    init(_ placement: WindowPlacement) {
        switch placement {
        case .leftHalf: self.init("Tile Window Left Half", "Left half of the screen", "Window tiled to the left half", ["left", "left half", "tile left", "left side", "left screen"], "rectangle.lefthalf.inset.filled", "LH")
        case .rightHalf: self.init("Tile Window Right Half", "Right half of the screen", "Window tiled to the right half", ["right", "right half", "tile right", "right side", "right screen"], "rectangle.righthalf.inset.filled", "RH")
        case .topHalf: self.init("Tile Window Top Half", "Top half of the screen", "Window tiled to the top half", ["top", "top half", "tile top", "upper half", "top side"], "rectangle.tophalf.inset.filled", "TH")
        case .bottomHalf: self.init("Tile Window Bottom Half", "Bottom half of the screen", "Window tiled to the bottom half", ["bottom", "bottom half", "tile bottom", "lower half", "bottom side"], "rectangle.bottomhalf.inset.filled", "BH")
        case .topLeft: self.init("Tile Window Top Left", "Top-left quarter of the screen", "Window tiled to the top-left quarter", ["top left", "top-left", "upper left", "tl"], "rectangle.split.2x2", "TL")
        case .topRight: self.init("Tile Window Top Right", "Top-right quarter of the screen", "Window tiled to the top-right quarter", ["top right", "top-right", "upper right", "tr"], "rectangle.split.2x2", "TR")
        case .bottomLeft: self.init("Tile Window Bottom Left", "Bottom-left quarter of the screen", "Window tiled to the bottom-left quarter", ["bottom left", "bottom-left", "lower left", "bl"], "rectangle.split.2x2", "BL")
        case .bottomRight: self.init("Tile Window Bottom Right", "Bottom-right quarter of the screen", "Window tiled to the bottom-right quarter", ["bottom right", "bottom-right", "lower right", "br"], "rectangle.split.2x2", "BR")
        case .leftThird: self.init("Tile Window Left Third", "Left third of the screen", "Window tiled to the left third", ["left third", "third left", "left 1/3"], "rectangle.split.3x1", "L3")
        case .centerThird: self.init("Tile Window Center Third", "Center third of the screen", "Window tiled to the center third", ["center third", "middle third", "center column"], "rectangle.split.3x1", "C3")
        case .rightThird: self.init("Tile Window Right Third", "Right third of the screen", "Window tiled to the right third", ["right third", "third right", "right 1/3"], "rectangle.split.3x1", "R3")
        case .leftTwoThirds: self.init("Tile Window Left Two Thirds", "Left two thirds of the screen", "Window tiled to the left two thirds", ["left two thirds", "left 2/3", "two thirds left"], "rectangle.leadinghalf.inset.filled", "L⅔")
        case .centerTwoThirds: self.init("Tile Window Center Two Thirds", "Center two thirds of the screen", "Window tiled to the center two thirds", ["center two thirds", "middle two thirds", "center 2/3"], "rectangle.center.inset.filled", "C⅔")
        case .rightTwoThirds: self.init("Tile Window Right Two Thirds", "Right two thirds of the screen", "Window tiled to the right two thirds", ["right two thirds", "right 2/3", "two thirds right"], "rectangle.trailinghalf.inset.filled", "R⅔")
        case .firstFourth: self.init("Tile Window First Fourth", "First quarter column of the screen", "Window tiled to the first fourth", ["first fourth", "first quarter", "fourth 1", "1/4 left"], "rectangle.split.3x1", "F1")
        case .secondFourth: self.init("Tile Window Second Fourth", "Second quarter column of the screen", "Window tiled to the second fourth", ["second fourth", "second quarter", "fourth 2"], "rectangle.split.3x1", "F2")
        case .thirdFourth: self.init("Tile Window Third Fourth", "Third quarter column of the screen", "Window tiled to the third fourth", ["third fourth", "third quarter", "fourth 3"], "rectangle.split.3x1", "F3")
        case .lastFourth: self.init("Tile Window Last Fourth", "Last quarter column of the screen", "Window tiled to the last fourth", ["last fourth", "last quarter", "fourth 4", "1/4 right"], "rectangle.split.3x1", "F4")
        case .firstThreeFourths: self.init("Tile Window First Three Fourths", "Left three quarters of the screen", "Window tiled to the first three fourths", ["first three fourths", "left three quarters", "3/4 left"], "rectangle.leadinghalf.inset.filled", "L¾")
        case .lastThreeFourths: self.init("Tile Window Last Three Fourths", "Right three quarters of the screen", "Window tiled to the last three fourths", ["last three fourths", "right three quarters", "3/4 right"], "rectangle.trailinghalf.inset.filled", "R¾")
        case .almostMaximize: self.init("Almost Maximize Window", "Fill 90% of the screen, centered", "Window almost maximized", ["almost maximize", "almost max", "nearly full", "90%"], "arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", "AM")
        case .maximizeHeight: self.init("Maximize Window Height", "Full height, same width and position", "Window height maximized", ["maximize height", "full height", "stretch vertically", "tall"], "arrow.up.and.down", "MH")
        case .centerHalf: self.init("Tile Window Center Half", "Center half of the screen, full height", "Window tiled to the center half", ["center half", "middle half", "center column wide"], "rectangle.center.inset.filled", "CH")
        case .maximize: self.init("Maximize Window", "Fill the visible screen", "Window maximized", ["maximize", "max", "fill", "fill screen", "fit screen", "full size", "zoom"], "arrow.up.left.and.arrow.down.right", "MX")
        case .center: self.init("Center Window", "Center at its current size", "Window centered", ["center", "recenter", "center window", "move to center"], "rectangle.center.inset.filled", "CT")
        case .increaseSize: self.init("Grow Window", "Grow the window", "Window enlarged", ["grow", "bigger", "larger", "enlarge", "resize bigger", "increase size"], "arrow.up.left.and.arrow.down.right", "GR")
        case .decreaseSize: self.init("Shrink Window", "Shrink the window", "Window shrunk", ["shrink", "smaller", "resize smaller", "decrease size"], "arrow.down.right.and.arrow.up.left", "SH")
        case .nudgeLeft: self.init("Nudge Window Left", "Move the window a few points left", "Window nudged left", ["nudge left", "move left", "shift left", "nudge"], "arrow.left", "NL")
        case .nudgeRight: self.init("Nudge Window Right", "Move the window a few points right", "Window nudged right", ["nudge right", "move right", "shift right"], "arrow.right", "NR")
        case .nudgeUp: self.init("Nudge Window Up", "Move the window a few points up", "Window nudged up", ["nudge up", "move up", "shift up"], "arrow.up", "NU")
        case .nudgeDown: self.init("Nudge Window Down", "Move the window a few points down", "Window nudged down", ["nudge down", "move down", "shift down"], "arrow.down", "ND")
        case .nextDisplay: self.init("Move Window to Next Display", "Move to the next connected display", "Window moved to the next display", ["next display", "next screen", "next monitor", "move next display"], "rectangle.on.rectangle.angled", "NX")
        case .previousDisplay: self.init("Move Window to Previous Display", "Move to the previous connected display", "Window moved to the previous display", ["previous display", "previous screen", "previous monitor", "prev display"], "rectangle.on.rectangle", "PV")
        case .restore: self.init("Restore Window Frame", "Undo the last window change", "Restored the previous window frame", ["restore", "undo tile", "undo resize", "undo window", "restore frame", "previous size"], "arrow.uturn.backward.circle", "RS")
        }
    }

    private init(_ title: String, _ subtitle: String, _ successMessage: String, _ aliases: [String], _ icon: String, _ fallback: String) {
        self.title = title
        self.subtitle = subtitle
        self.successMessage = successMessage
        self.aliases = aliases
        self.icon = icon
        self.fallback = fallback
    }
}
