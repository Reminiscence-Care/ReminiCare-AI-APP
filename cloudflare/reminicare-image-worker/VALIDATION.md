# Validation — 2026-10-05

Deployed Worker: https://reminicare-image-api.hding49.workers.dev

| Operation | Elapsed |
| --- | ---: |
| Taiwanese opera | 15,337 ms |
| Traditional corner grocery store | 30,972 ms |
| Rice harvesting | 13,161 ms |
| Taiwan railway journey | 15,933 ms |
| First reference-image edit | 5,844 ms |
| Second successive edit | 4,575 ms |

All six requests succeeded and produced 1024×640 images. Reference-image edits preserved the broad scene and number of people, but some face details and positions changed. Historical train details and generated signage are illustrative, not verified historical facts. Images are intended as conversation stimuli and require user confirmation.

The first smoke run edited the railway scene because the scene map was unordered. The script now uses a fixed order so subsequent smoke runs edit the rice-harvest scene. Output images are retained in the ignored `smoke-output/` directory.

Worker type checking and 13 tests passed. Flutter analysis and 38 tests passed; Windows debug and Android debug builds succeeded. iOS compilation and physical iPad microphone, audio lifecycle, network and memory checks require macOS/iPad and were not performed on this Windows host.
