namespace CallCodingClis

module Help =

    open System
    open System.Diagnostics

    let private canonicalRunners =
        [ ("opencode", "oc")
          ("claude", "cc")
          ("kimi", "k")
          ("codex", "rc")
          ("crush", "cr") ]

    let helpText =
        """ccc — call coding CLIs

Usage:
  ccc [runner] [+thinking] [:provider:model] [@alias] "<Prompt>"
  ccc --help
  ccc -h

Slots (in order):
  runner        Select which coding CLI to use (default: oc)
                opencode (oc), claude (cc), kimi (k), codex (rc), crush (cr)
  +thinking     Set thinking level: +0 (off) through +4 (max)
  :provider:model  Override provider and model
  @alias        Use a named preset from config

Examples:
  ccc "Fix the failing tests"
  ccc oc "Refactor auth module"
  ccc cc +2 :anthropic:claude-sonnet-4-20250514 "Add tests"
  ccc k +4 "Debug the parser"
  ccc codex "Write a unit test"

Config:
  ~/.config/ccc/config.toml  — default runner, aliases, abbreviations
"""

    let private getVersion (binary: string) : string =
        try
            let psi = ProcessStartInfo(binary, "--version")
            psi.UseShellExecute <- false
            psi.RedirectStandardOutput <- true
            psi.RedirectStandardError <- false
            let proc = Process.Start(psi)
            if proc.WaitForExit(3000) && proc.ExitCode = 0 then
                let output = proc.StandardOutput.ReadToEnd().Trim()
                if not (String.IsNullOrEmpty(output)) then
                    output.Split('\n').[0]
                else
                    ""
            else
                ""
        with
        | _ -> ""

    let private which (name: string) : bool =
        try
            let psi = ProcessStartInfo("which", name)
            psi.UseShellExecute <- false
            psi.RedirectStandardOutput <- true
            psi.RedirectStandardError <- true
            let proc = Process.Start(psi)
            proc.WaitForExit() |> ignore
            proc.ExitCode = 0
        with
        | _ -> false

    let runnerChecklist () : string =
        let lines = ResizeArray<string>()
        lines.Add("Runners:")
        for name, alias in canonicalRunners do
            let binary =
                match Parser.runnerRegistry.TryFind(name) with
                | Some info -> info.Binary
                | None -> name
            let found = which binary
            if found then
                let version = getVersion binary
                let tag = if not (String.IsNullOrEmpty(version)) then version else "found"
                lines.Add(sprintf "  [+] %-10s (%s)  %s" name binary tag)
            else
                lines.Add(sprintf "  [-] %-10s (%s)  not found" name binary)
        String.Join("\n", lines)

    let printHelp () : unit =
        printfn "%s" (helpText.TrimEnd())
        printfn ""
        printfn "%s" (runnerChecklist ())

    let printUsage () : unit =
        eprintfn "usage: ccc [runner] [+thinking] [:provider:model] [@alias] \"<Prompt>\""
        eprintfn "%s" (runnerChecklist ())
