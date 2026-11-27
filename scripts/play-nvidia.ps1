# Starts the title on an NVIDIA card with the Series S settings measured on an RTX 5070 (about 18-22 fps, no device loss).
#   scripts\play-nvidia.ps1 -Exe <path of your own copy's executable>
# -NoSmoothMotion  run target\<build>\victory.exe itself. By default a copy named victory_sm.exe is started instead,
#                  so a Smooth Motion profile set for that exe in the NVIDIA App applies every time.
# -SeriesX         the Series X profile instead (slower: about 7 fps at half scale)
# -Quality         fewer stretched/jumping bodies and less rainbow skin, at about 13 fps instead of about 20
# -RayTracing      keep the title's ray-tracing passes (off by default: see below)
# -Resolution      the height the game renders at before the title's own upscaler: 2160, 1440, 1080, 720, 540 or 480.
#                  Series S outputs 1080p (so up to 1080 there), Series X 2160p. Default: half the output (540 on S,
#                  1080 on X). The play-S-*.ps1 and play-X-*.ps1 scripts next to this one call it with each.
# -Adapter         on a PC with more than one card, the one to use: part of its name (-Adapter 5060) or its index
#                  (-Adapter '#1'). Default: Windows' default card (the one the main display is on).
# -Build           target\diag (the default, the build all measurements are of) or target\release
#                  (the release build ignores the ray-tracing skip list: VICTORY_SKIP_PIPELINES is a diagnostics switch)
# -WindowsBarMB    maximum MiB of title memory windows in CPU-mapped VRAM (by default 3072 on PCs with under
#                  24 GB of RAM, else 0; -WindowsBarMB 0 turns it off).
# -CardBuffersMinKB  smallest title buffer, in KiB, whose copy and compares go to the card's memory (by default 64
#                  on cards with 8 GB of VRAM or less, else the 1 MiB of VICTORY_CARD_BUFFERS_MIN_MB;
#                  -CardBuffersMinKB 0 keeps 1 MiB).
# -More           other settings: -More @{VICTORY_PANEL='1'}
# Run it from a normal window, not as administrator: the driver then keeps its shader cache elsewhere.
param(
    [Parameter(Mandatory)][string]$Exe,
    [switch]$NoSmoothMotion,
    [switch]$SeriesX,
    [switch]$Quality,
    [switch]$RayTracing,
    [ValidateSet('2160', '1440', '1080', '720', '540', '480')][string]$Resolution,
    [string]$Adapter,
    [ValidateSet('diag', 'release')][string]$Build = 'diag',
    [hashtable]$More = @{},
    [uint32]$WindowsBarMB,
    [uint32]$CardBuffersMinKB
)

# Dedicated memory in bytes of the card -Adapter names by part of its name, else of the NVIDIA card with the most
# (Windows' display class keys; Win32_VideoController stops at 4 GB). 0 when it cannot be read.
function Get-CardMemory([string]$adapterName) {
    $class = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    $cards = try {
        Get-ChildItem -LiteralPath $class -ErrorAction Stop | Where-Object { $_.PSChildName -match '^\d{4}$' } | ForEach-Object {
            $key = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            $bytes = $key.'HardwareInformation.qwMemorySize'
            if ($key.DriverDesc -and $bytes) { [pscustomobject]@{ Name = [string]$key.DriverDesc; Bytes = [uint64]$bytes } }
        }
    } catch { @() }
    $pattern = if ($adapterName -and -not $adapterName.StartsWith('#')) { "*$adapterName*" } else { '*NVIDIA*' }
    $match = @($cards | Where-Object { $_.Name -like $pattern } | Sort-Object Bytes -Descending)
    if ($match.Count -gt 0) { $match[0].Bytes } else { 0 }
}
$settings = @{
    # This fork's play set (scripts\play.ps1, not -Safe): the speed set.
    VICTORY_TEXTURE_NO_WAIT = '1'; VICTORY_RELAY = '2'; VICTORY_CARD_STEPS = '2'
    VICTORY_WIDE_BACK = '1'; VICTORY_CARD_REHASH_RUNS = '1'
    VICTORY_JOIN_COPIES = '1'; VICTORY_INDIRECT_WINDOW = '1'; VICTORY_RELAY_COPY = '1'
    VICTORY_INDIRECT_BATCH = '2'; VICTORY_MAP_THREADS = '1'; VICTORY_TITLE_PRIORITIES = '0'; VICTORY_CARD_AWAKE = '1'
    VICTORY_SHOW_AFTER = '1'; VICTORY_AMBIENT = '0.8'; VICTORY_D3D12_DRED = 'light'; VICTORY_SKIP_PIPELINES = 'none'
    # Deferred list recording can wash out the whole 3D scene on NVIDIA (7900XTX fork issues #112 and #62).
    VICTORY_THIN = '0'; VICTORY_JOIN_PARTS = '8'; VICTORY_UPLOAD_AHEAD = '1'
    # Cheap picture fixes, on in both sets:
    # - Overbright views: without rays the light probes keep the sky's light indoors. The fog is bounded by 1.5 times
    #   the light around, and what the title left by 2 times the estimate (was 4; ambient.rs).
    VICTORY_AMBIENT_AIR = '1.5'; VICTORY_AMBIENT_MOST = '2'
    # - Black blobs: a NaN a shader writes is made 0 before blur and the temporal upscaler spread it (emit/lower.rs).
    VICTORY_NAN_SCRUB = '1'
    # Wait for new shaders rather than skip their draws (a hitch the first time a place is seen). Each pipeline is
    # waited for at most once (VICTORY_PIPELINE_WAIT_ONCE, on by default): one that takes longer no longer stops the
    # picture in every frame it is in view (pipeline/make.rs).
    VICTORY_PIPELINE_WAIT_MS = '10000'
    # NVIDIA caps the shader-visible view heap at 1,000,000: without more dynamic slots thousands of draws a frame
    # are dropped (descriptor/host.rs dynamic_slots).
    VICTORY_DYNAMIC_SLOTS = '524288'
    # Half render scale with the title's own upscaler (Series S needs it with a scale below 1; victory-loader hooks.rs).
    VICTORY_RENDER_SCALE = '0.5'; VICTORY_OWN_UPSCALER = '1'
    # Ray walks end at the root while the structure builder is off (emit/intersect.rs).
    VICTORY_BVH_MISS = '1'
    # Memory compares on the card instead of the CPU: 11 -> about 22 fps on Series S.
    VICTORY_CARD_BUFFERS_MIN_MB = '1'; VICTORY_CARD_BUFFERS_MB = '1536'
    # Series S presents the interface as a second plane: laid over the game (compose.rs), else black before gameplay.
    VICTORY_COMPOSE = '1'
}
# Ray tracing mostly off. The structure builder cannot run on NVIDIA (its 64-lane programs are refused; upstream
# Marvisak/VIctory pull request 2311), so every ray misses, and the passes that turn misses into light made rooms go
# white depending on the view angle. rt_off_hashes.txt lists the 1,000 CS_RaytracingResolve and 34 traced-shadow
# shaders, which are skipped. The screen-probe and visibility traces keep running: skipping those too left their
# outputs as garbage (rainbow glitter everywhere).
$rtList = Join-Path $PSScriptRoot 'rt_off_hashes.txt'
if (-not $RayTracing -and (Test-Path -LiteralPath $rtList -PathType Leaf)) {
    $settings.VICTORY_SKIP_PIPELINES = (Get-Content -LiteralPath $rtList -Raw).Trim()
}
if ($Quality) {
    # Stretched/jumping bodies: relay stage 1 and no card steps (avatarmanz/VIctory-7900XTX issue 13,
    # fxceless/victory-fork issue 89). Rainbow skin: texture refreshes wait for the runtime's remapping.
    # Costs about 7 fps (the submitting thread waits about 30 ms a frame for the card).
    $settings.VICTORY_RELAY = '1'; $settings.VICTORY_CARD_STEPS = '0'; $settings.VICTORY_TEXTURE_NO_WAIT = '0'
}
# The render scale is the rendered height over the output height (Series S 1080, Series X 2160).
$outHeight = if ($SeriesX) { 2160 } else { 1080 }
$console = if ($SeriesX) { 'X' } else { 'S' }
if ($Resolution) {
    if ([int]$Resolution -gt $outHeight) {
        Write-Host "Series $console outputs ${outHeight}p: ${Resolution}p is above it."
        exit 1
    }
    $settings.VICTORY_RENDER_SCALE = ([int]$Resolution / $outHeight).ToString('0.####', [Globalization.CultureInfo]::InvariantCulture)
}
if ($Adapter) { $settings.VICTORY_ADAPTER = $Adapter }
if ($PSBoundParameters.ContainsKey('WindowsBarMB')) {
    $settings.VICTORY_WINDOWS_BAR_MB = $WindowsBarMB.ToString([Globalization.CultureInfo]::InvariantCulture)
} else {
    # Without -WindowsBarMB, PCs with under 24 GB of RAM get 3072 (PR #6). Windows lets a card share at most half
    # the RAM, and the windows filled that on a 16 GB PC (RTX 3060) about a minute into the world (0x8007000E, then
    # a driver fault). 32 GB and more never got there, so they keep the runtime default (0, off).
    $ram = try { (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory } catch { 0 }
    if ($ram -gt 0 -and $ram -lt 24GB) {
        $settings.VICTORY_WINDOWS_BAR_MB = '3072'
        Write-Host "$([math]::Round($ram / 1GB)) GB of RAM: title memory windows in the card's memory the CPU maps, up to 3 GB (-WindowsBarMB 0 turns this off)"
    }
}
if ($PSBoundParameters.ContainsKey('CardBuffersMinKB')) {
    if ($CardBuffersMinKB -gt 0) {
        $settings.VICTORY_CARD_BUFFERS_MIN_KB = $CardBuffersMinKB.ToString([Globalization.CultureInfo]::InvariantCulture)
    }
} else {
    # On 8 GB cards every copy of a title buffer is under 1 MiB (341-392 ranges of about 90 KB a frame), so
    # VICTORY_CARD_BUFFERS_MIN_MB=1 moved none of them and shaders reached them over the bus. From 64 KiB up on the
    # card: RTX 3070 8 GB, Series S 720p Quality, 10.5 -> 14.5 fps, GPU 51.6 -> 27.4 ms a frame (issue #1).
    $vram = Get-CardMemory $Adapter
    if ($vram -gt 0 -and $vram -le 8GB) {
        $settings.VICTORY_CARD_BUFFERS_MIN_KB = '64'
        Write-Host "$(($vram / 1GB).ToString('0.#', [Globalization.CultureInfo]::InvariantCulture)) GB card: title buffers from 64 KiB up in the card's memory (-CardBuffersMinKB 0 turns this off)"
    }
}
foreach ($k in $More.Keys) { $settings[$k] = $More[$k] }
$scale = [double]::Parse($settings.VICTORY_RENDER_SCALE, [Globalization.CultureInfo]::InvariantCulture)
Write-Host "Series $console, rendering at $([int]($outHeight * $scale))p (render scale $($settings.VICTORY_RENDER_SCALE))"

$victory = Join-Path $PSScriptRoot "..\target\$Build\victory.exe"
if (-not (Test-Path -LiteralPath $victory -PathType Leaf)) { Write-Host "No $victory. Build it first (README.md)."; exit 1 }
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) { Write-Host "No $Exe."; exit 1 }
if (-not $NoSmoothMotion) {
    # A copy under the name the NVIDIA App's Smooth Motion profile is set for, refreshed when the build changes.
    $sm = Join-Path (Split-Path $victory) 'victory_sm.exe'
    if (-not (Test-Path -LiteralPath $sm -PathType Leaf) -or (Get-Item -LiteralPath $sm).LastWriteTime -lt (Get-Item -LiteralPath $victory).LastWriteTime) {
        Copy-Item -LiteralPath $victory -Destination $sm -Force -ErrorAction Stop
    }
    $victory = $sm
}
# (Other settings left over in this window go; where your files are stays.)
$paths = 'VICTORY_CONFIG', 'VICTORY_GAME_DIR', 'VICTORY_CACHE_DIR', 'VICTORY_DATA_DIR'
Get-ChildItem Env:VICTORY_* | Where-Object { $_.Name -notin $paths } | ForEach-Object { Remove-Item "Env:$($_.Name)" }
foreach ($k in $settings.Keys) { Set-Item "Env:$k" $settings[$k] }
$Exe = (Resolve-Path -LiteralPath $Exe).Path
$runArgs = @('run', $Exe, '--execute')
if (-not $SeriesX) { $runArgs += @('--console', 'series-s') }
Push-Location -LiteralPath (Join-Path $PSScriptRoot '..')   # victory.toml is looked for here
try {
    & $victory @runArgs
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $exitCode
