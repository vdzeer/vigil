import Foundation
import Testing

@testable import VigilCore

@Suite struct LidModeTests {
    static let pmsetOn = """
        System-wide power settings:
         SleepDisabled\t\t1
        Currently in use:
         standby              1
         sleep                1 (sleep prevented by Vigil)
        """

    @Test func readsSleepDisabledFromPmset() {
        #expect(LidMode.isOn(pmsetOutput: Self.pmsetOn))
        #expect(!LidMode.isOn(pmsetOutput: Self.pmsetOn.replacingOccurrences(of: "\t\t1", with: "\t\t0")))
        #expect(!LidMode.isOn(pmsetOutput: ""))
    }

    @Test func doesNotMistakeAnotherNumberForTheSetting() {
        #expect(!LidMode.isOn(pmsetOutput: " SleepDisabled\t\t10\n"))
        #expect(!LidMode.isOn(pmsetOutput: " NotSleepDisabled 1\n"))
    }

    @Test func theWatchdogSwitchesTheModeOffOnlyAfterTheAppIsGone() {
        let line = LidWatchdog.script(pid: 4321, uid: 501)
        #expect(line.hasPrefix("while /bin/kill -0 4321 "))
        #expect(line.contains("/usr/bin/pgrep -xq -U 501 Vigil || /usr/bin/sudo -n /usr/bin/pmset -a disablesleep 0"))
        // Every command in the line is called by its full path.
        let commands = line.split(separator: ";").flatMap { $0.split(separator: "|") }.compactMap {
            $0.split(separator: " ").first { !["while", "do", "done", "||", ""].contains($0) }
        }
        #expect(commands.allSatisfy { $0.hasPrefix("/") }, "\(commands)")
    }

    @Test func quotesForTheShell() {
        #expect(LidMode.shellQuoted("plain") == "'plain'")
        #expect(LidMode.shellQuoted("it's") == #"'it'\''s'"#)
    }

    @Test func quotesForAppleScript() {
        #expect(LidMode.scriptQuoted(#"say "hi" \ bye"#) == #""say \"hi\" \\ bye""#)
    }

    /// Runs the setup line through a real shell the way `do shell script` would, with `echo` in
    /// place of the script, and checks that hostile names arrive as two plain arguments.
    @Test(arguments: [
        "/Applications/Vigil.app/Contents/Resources/allow-lid-closed.sh",
        "/Users/a b/Vigil's \"copy\"/x.sh",
        "/tmp/$(touch pwned)/`id`;rm -rf ~/x.sh",
    ])
    func hostilePathsStayOneArgument(path: String) throws {
        let line = LidMode.setupScript(script: path, user: "o'neil")
        // Undo the AppleScript layer: the command is the first quoted string.
        let start = try #require(line.range(of: "do shell script \""))
        let afterStart = line[start.upperBound...]
        var command = ""
        var escaped = false
        for character in afterStart {
            if escaped {
                command.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                break
            } else {
                command.append(character)
            }
        }
        #expect(command.hasPrefix("'"))
        let echoed = command.replacingOccurrences(
            of: LidMode.shellQuoted(path), with: "printf '%s\\n' " + LidMode.shellQuoted(path))
        // printf repeats its format for every argument: the path, then `--user` and the name.
        let output = run("/bin/sh", ["-c", echoed]).output
        #expect(output == path + "\n--user\no'neil\n")
    }
}
