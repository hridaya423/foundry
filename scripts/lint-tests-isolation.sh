#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TESTS="${1:-$ROOT/Tests/FoundryTests}"

find "$TESTS" -name '*.swift' -print0 | xargs -0 perl -0777 -e '
my $helper = qr{/Helpers/IsolatedMachine\.swift$};
my $window = qr{requireWindowTestsEnabled\(\)};
my $balanced = qr{(?<p>\((?:[^()]++|(?&p))*\))};
my @forbidden = (
    [qr{(?<![\w.])CommandPanelState\(}, "use CommandPanelState.isolated(", 1],
    [qr{(?<![\w.])ActionRunner\(}, "use ActionRunner.isolated(", 1],
    [qr{(?<![\w.])DirectPasteService\(}, "use DirectPasteService.isolated(", 1],
    [qr{NSPasteboard\.general}, "never touch the general pasteboard", 1],
    [qr{SystemPasteboardClient\(\)}, "never read the system pasteboard", 1],
    [qr{DirectPasteService\.shared}, "never use the shared paste service", 1],
    [qr{ClipboardHistoryStore\(\)}, "never open the real clipboard database", 1],
    [qr{FileManager\.default\.trashItem}, "never trash through the real Trash", 1],
    [qr{LauncherRival\.all}, "never reach the real Raycast or Alfred preferences", 1],
    [qr{SpotlightShortcut\.(?:disableOnThisMac|setEnabled\(\w+\))}, "never write the real Spotlight shortcut", 1],
    [qr{UserDefaults\(suiteName:\s*"}, "name suites through isolatedDefaultsSuite(", 0],
    [qr{\.(?:pasteSelectedEmoji|pasteFromClipboard)\(}, "writes or reads the general pasteboard", 1],
    [qr{AgentEventSocketServer\.socketURL}, "never use the live agent socket path", 1],
    [qr{(?<![\w.])(?:ShellController|OnboardingWindowController|StatusItemController|HotkeyController|PanelController)\(},
        "opens windows or registers hotkeys: call requireWindowTestsEnabled() in the test", 2],
);
my @needs = (
    [qr{(?<![\w.])ClipboardHistoryState}, qr{pasteboard:}, "pass pasteboard:"],
    [qr{(?<![\w.])OnboardingState}, qr{registerLoginItem:}, "pass registerLoginItem:"],
    [qr{(?<![\w.])OnboardingState}, qr{importSources:}, "pass importSources:"],
    [qr{(?<![\w.])OnboardingState}, qr{localState:}, "pass localState:"],
    [qr{(?<![\w.])AgentEventSocketServer}, qr{socketURL:}, "pass socketURL:"],
    [qr{(?<![\w.])AgentMonitorState}, qr{socketURL:}, "pass socketURL: or use AgentMonitorState.isolated("],
);
my $bad = 0;
sub line { my ($text, $pos) = @_; return 1 + (substr($text, 0, $pos) =~ tr/\n//); }
sub report { my ($file, $text, $pos, $message) = @_; print STDERR "$file:" . line($text, $pos) . ": $message\n"; $bad++; }
for my $file (@ARGV) {
    next if $file =~ $helper;
    open(my $fh, "<", $file) or die "$file: $!";
    local $/;
    my $text = <$fh>;
    close $fh;
    my $code = join("\n", map { s{^\s*//.*$}{}r } split(/\n/, $text, -1));
    my $gated = $code =~ $window;
    for my $rule (@forbidden) {
        my ($pattern, $message, $mode) = @$rule;
        while ($code =~ /$pattern/g) {
            next if $mode == 2 && $gated;
            report($file, $code, $-[0], $message);
        }
    }
    if ($code =~ /UserDefaults\(suiteName:/ && $code !~ /isolatedDefaultsSuite\(/) {
        report($file, $code, $-[0], "UserDefaults suites must come from isolatedDefaultsSuite(");
    }
    for my $rule (@needs) {
        my ($pattern, $label, $message) = @$rule;
        while ($code =~ /$pattern$balanced/g) {
            my $call = $&;
            report($file, $code, $-[0], "$message in $call") unless $call =~ $label;
        }
    }
}
exit($bad ? 1 : 0);
' || { echo "error: tests reach a real machine resource; use the injected seams in Tests/FoundryTests/Helpers/IsolatedMachine.swift" >&2; exit 1; }

echo "lint-tests-isolation: ok"
