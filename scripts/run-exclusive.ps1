# Runs a heavy command (full test suite, full build) while holding a machine-wide
# lock, so parallel agents queue instead of competing for CPU and memory.
#
# Usage: pwsh -NoProfile -File ~/.claude/scripts/run-exclusive.ps1 [-TimeoutSec N] [--] <command> [args...]
#
# - The lock is the named mutex Global\claude-heavy-run, shared by every process,
#   worktree and repository on the machine. Windows releases it if the holder dies,
#   so a crashed run never leaves a stale lock.
# - -TimeoutSec limits the run itself, counted from when the lock is acquired, not
#   the time spent queueing. On timeout the whole process tree is killed and the
#   exit code is 124, as with coreutils timeout.
# - The command runs at BelowNormal priority; its children inherit that.
# - The command's exit code is passed through.
# - Nested calls (a wrapped command that calls the wrapper again) run directly
#   rather than deadlocking, detected through CLAUDE_EXCLUSIVE_HELD.
# - Set CLAUDE_EXCLUSIVE_DISABLE=1 to bypass the lock entirely.
# - CLAUDE_EXCLUSIVE_NAME overrides the mutex name (used by the tests).
#
# Arguments are parsed by hand rather than with a param block so the wrapped
# command's own switches (-t, -n, ...) are never bound to the wrapper's parameters.
$ErrorActionPreference = 'Stop'

$timeoutSec = 0
$rest = [System.Collections.Generic.List[string]]::new()
$i = 0
while ($i -lt $args.Count) {
    $a = [string]$args[$i]
    if ($rest.Count -eq 0 -and $a -eq '-TimeoutSec') { $timeoutSec = [int]$args[$i + 1]; $i += 2; continue }
    if ($rest.Count -eq 0 -and $a -eq '--') { $i++; while ($i -lt $args.Count) { $rest.Add([string]$args[$i]); $i++ }; break }
    $rest.Add($a); $i++
}
if ($rest.Count -eq 0) {
    [Console]::Error.WriteLine('run-exclusive: usage: run-exclusive.ps1 [-TimeoutSec N] [--] <command> [args...]')
    exit 2
}

# Resolve to an executable file (npm -> npm.cmd), never a .ps1 shim, so the
# execution policy does not matter.
$exe = $rest[0]
$cmd = Get-Command $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $cmd) {
    [Console]::Error.WriteLine("run-exclusive: command not found: $exe")
    exit 127
}

$lockName = if ($env:CLAUDE_EXCLUSIVE_NAME) { $env:CLAUDE_EXCLUSIVE_NAME } else { 'Global\claude-heavy-run' }
$useLock = -not $env:CLAUDE_EXCLUSIVE_HELD -and $env:CLAUDE_EXCLUSIVE_DISABLE -ne '1'
$mutex = $null
$owned = $false
try {
    if ($useLock) {
        $mutex = [System.Threading.Mutex]::new($false, $lockName)
        $waitStart = Get-Date
        try { $owned = $mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $owned = $true }
        if (-not $owned) {
            [Console]::Error.WriteLine("run-exclusive: another heavy run holds the lock; waiting ($($rest -join ' '))")
            try { $owned = $mutex.WaitOne() } catch [System.Threading.AbandonedMutexException] { $owned = $true }
            $waited = [int]((Get-Date) - $waitStart).TotalSeconds
            [Console]::Error.WriteLine("run-exclusive: lock acquired after ${waited}s")
        }
        $env:CLAUDE_EXCLUSIVE_HELD = '1'
    }

    # Lower this process first so the child and its descendants inherit it from birth.
    try { (Get-Process -Id $PID).PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal } catch { }
    $psi = [System.Diagnostics.ProcessStartInfo]::new($cmd.Source)
    for ($j = 1; $j -lt $rest.Count; $j++) { $psi.ArgumentList.Add($rest[$j]) }
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)

    if ($timeoutSec -gt 0) {
        if (-not $p.WaitForExit($timeoutSec * 1000)) {
            [Console]::Error.WriteLine("run-exclusive: timed out after ${timeoutSec}s; killing process tree")
            $p.Kill($true)
            $p.WaitForExit()
            exit 124
        }
    }
    $p.WaitForExit()
    exit $p.ExitCode
}
finally {
    if ($owned) { $mutex.ReleaseMutex() }
    if ($mutex) { $mutex.Dispose() }
}
