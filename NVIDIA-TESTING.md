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

## RTX 2080 / FSR4 ACO (2026-11-27)

One run on Windows 11 26100, Ryzen 5 5600GT, 16 GB RAM, GeForce RTX 2080 8 GB, driver 621.24, with the `diag` build and a cold shader cache. The title was the Series S profile at 720p internal, 1080p output, with the title's FSR4 upscaler selected instead of the own upscaler:

```powershell
.\scripts\play-S-720p.ps1 -Exe 'E:\DLs\GTAVI\game_scarlett_master.exe' -NoSmoothMotion -More @{VICTORY_OWN_UPSCALER='0'}
```

- FSR4 initialized without a configuration error and reported `compute PSO created via ACO ('ACCC')` for all 29 passes. Before the console compute-pipeline change it reported `DeserializeComputePipelineStateX FAILED ... falling back to NewBE` for every pass.
- The prologue reached the world and rendered the close-up correctly. After the first-frame pipeline work it measured about 7 fps / 135.7 ms per frame at 720p internal, with the usual first-visit shader stalls.
- Three of the 29 passes are 64-lane (wave64) programs (`17af85f170e66f30`, `477b52e73ddeb6f2`, `8b437ab61d8008fe`) and still fail to translate on a 32-lane host: "a lane mask exchanged where not every lane runs". Their dispatches are dropped. The image was still complete in the tested view.
- 540p cannot use FSR4. The DLL requires a 1280x720 or 1920x1080 render size; at 960x540 it logs `maxRenderSize must be 1280x720 ... received 960x540` and falls back. Use the own upscaler at 540p for the playable profile on this card.
- Not tested: FSR4 at 1080p internal, the `-Quality` preset with FSR4, a full gameplay route, peak VRAM, and long-run device loss.

## Sharing code with the AMD megafork

The NVIDIA line and the [AMD line](https://github.com/rorodev6/victory-megafork-amd) have a common ancestor (`0a435665`), but their renderers have diverged. Port focused patches and run the appropriate tests on each base. Maintain separate launch defaults for shader wave execution, descriptor budgets and upscaling. Compare related fixes on both GPUs before treating them as cross-vendor defaults.

The first shared fix is [Filip722's pipeline job completion change from fxceless](https://github.com/fxceless/victory-fork/pull/1353). It completes a failed job after a Rust panic and wakes waiters. This is a defensive recovery for Rust errors. Driver resets still need separate diagnosis. The Git history retains upstream authorship and the [README credits](README.md#credits) retain the project's upstream acknowledgements.
