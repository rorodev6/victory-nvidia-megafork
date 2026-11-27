# NVIDIA testing guide

## Base and benchmarks

Start from [trustno1-coder `6a31e431`](https://github.com/trustno1-coder/VIctory-NVIDIA/commit/6a31e431). It has an NVIDIA-specific launch profile, a Series S interface compositor, and settings for texture synchronization and descriptor capacity. The upstream README reports about 20–22 FPS indoors on an RTX 5070 in Series S at half render scale. A [separate RTX 5080 report](https://github.com/fxceless/victory-fork/issues/1379) reaches about 25 FPS with a stack of additional patches. A [separate RTX 4080 test](https://github.com/fxceless/victory-fork/issues/1268) reports 27.2 FPS median with another mix of patches. Those numbers describe the listed configurations and scenes.

Cool Fox `30e54b4` is a valuable reference for texture synchronization and frame time. Its package reports about 30 FPS median on an RTX 4090. Use that as a comparison target for individual fixes. [Geckomacabre](https://github.com/Geckomacabre/vx-layer) is another candidate source for sampler handling and reducing GPU waits. [Kelvaroq](https://github.com/stellarr-studio/kelvaroq) is worth tracking for memory management, with its public benchmark kept separate from development previews.

## First run

Use the pinned Rust toolchain and the MSVC C++ build tools with a Windows SDK. On Windows 10, follow the [Agility SDK setup](README.md#windows-10-setup) before building. Build a diagnostics executable and start with the upstream Quality preset at 720p internal resolution. The runtime uses your own game files.

```powershell
cargo build --locked --profile diag -p victory --features diagnostics
.\scripts\play-nvidia.ps1 -Exe 'D:\Games\Example\game.exe' -Quality -Resolution 720 -NoSmoothMotion
```

Compare against the same command without `-Quality` after establishing the baseline. Record the commit, GPU, driver, CPU, RAM, cache state, internal and output resolution, and render settings. Capture the opening close-up and a fixed city route on RTX 5070, 4080/4090 and 5080-class hardware where available. Compare median and p95 frame times, missing faces or geometry, and device losses. Keep generated frames separate from rendered FPS.

## 8 GB cards

On 8 GB cards every copy of a title buffer is under 1 MiB, so `VICTORY_CARD_BUFFERS_MIN_MB=1` moves none of them to the card and shaders reach them over the bus ([issue #1](https://github.com/rorodev6/victory-nvidia-megafork/issues/1)). `play-nvidia.ps1` sets `VICTORY_CARD_BUFFERS_MIN_KB=64` on cards with 8 GB of VRAM or less; `-CardBuffersMinKB 0` turns it off.

RTX 3070 8 GB (driver 610.88), Ryzen 7 9700X, 32 GB RAM, Windows 11 26200, commit `79f36b3`, Series S, `-Quality -Resolution 720 -NoSmoothMotion`, warm cache, one run each of the same mission. Gameplay samples only (500 or more draws a frame):

| Settings | Run | Median fps | Median frame | p95 frame | Median GPU time |
|---|---|---|---|---|---|
| Baseline | 14 min | 10.5 | 95.4 ms | 121.7 ms | 51.6 ms |
| `-WindowsBarMB 3072` | 31 min | 9.9 | 100.8 ms | 136.9 ms | 50.6 ms |
| `-WindowsBarMB 3072`, `MIN_KB=64` | 18 min | 12.7 | 79.2 ms | 106.1 ms | 34.4 ms |
| `MIN_KB=64` | 7 min | 14.5 | 69.0 ms | 92.9 ms | 27.4 ms |

No device loss, out-of-memory error or panic in any run; the same 9 pipelines were refused in each. The gain is in GPU time, not in preparing frames. `-WindowsBarMB 3072` did not help on this card: its windows take VRAM the textures need. The routes were not identical and the last run is short, so read differences under about 5 % as noise.

## Sharing code with the AMD megafork

The NVIDIA line and the [AMD line](https://github.com/rorodev6/victory-megafork-amd) have a common ancestor (`0a435665`), but their renderers have diverged. Port focused patches and run the appropriate tests on each base. Maintain separate launch defaults for shader wave execution, descriptor budgets and upscaling. Compare related fixes on both GPUs before treating them as cross-vendor defaults.

The first shared fix is [Filip722's pipeline job completion change from fxceless](https://github.com/fxceless/victory-fork/pull/1353). It completes a failed job after a Rust panic and wakes waiters. This is a defensive recovery for Rust errors. Driver resets still need separate diagnosis. The Git history retains upstream authorship and the [README credits](README.md#credits) retain the project's upstream acknowledgements.
